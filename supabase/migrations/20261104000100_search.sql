-- F12 · Search (CAT-03, US-02; C-04, C-04a, C-04b).
--
-- * product_search keeps one search document per product: a weighted
--   tsvector (name A, brand B, category and its parents C) and a lowercased
--   haystack of the same text in English and Khmer. Triggers on products and
--   categories keep it current. Clients never read it; the functions below
--   do, and only ever return active products.
-- * Matching (search_matches) is any of:
--     - English full text with prefixes ("head" finds headphones,
--       "headphones" finds "Headphone" through the stemmer);
--     - a substring of the haystack. Khmer is written without spaces between
--       words, so "កាស" must find "កាសឥតខ្សែ";
--     - when neither finds anything, trigram word similarity >= 0.5 for
--       typos in queries of 4 or more characters ("headphnes", "backpak").
--   Heavier typos ("hedfones", 0.33) don't match; the no-results screen
--   offers search_did_you_mean instead, as in C-04b.
-- * catalog_browse takes the query (p_q) and a `relevance` sort, so search
--   results reuse every filter, facet, page and business-buyer rule of the
--   product list.
-- * search_vocabulary is every word (and two-word phrase) of active product
--   names, brands and categories. It feeds suggestions (C-04) and "Did you
--   mean" (C-04b), and is refreshed when names change.
-- * search_history keeps each signed-in shopper's recent searches;
--   search_log keeps every search with its result count and how long it
--   took in the app, for staff (US-02: under 1 s).

-- ---------------------------------------------------------------------------
-- Text helpers
-- ---------------------------------------------------------------------------

-- Lowercase, single spaces, at most 100 characters.
create function public.search_normalize(p_q text)
returns text
language sql
immutable
set search_path = ''
as $$
  select left(btrim(regexp_replace(lower(coalesce(p_q, '')), '\s+', ' ', 'g')), 100);
$$;

-- The query as a prefix tsquery ("wireless head" -> 'wireless':* &
-- 'head':*), stemmed (English) or as typed (simple), so neither stemming
-- nor stopwords ("he") lose a match. Latin letters and digits only: Khmer
-- is matched by substring. Null when there is nothing to look up. (A
-- stopword-only English half is empty; its notice is expected, so muted.)
create function public.search_tsquery(p_q text)
returns tsquery
language sql
immutable
set search_path = ''
set client_min_messages = warning
as $$
  select case when count(*) = 0 then null
              else to_tsquery('english', string_agg(t || ':*', ' & '))
                   || to_tsquery('simple', string_agg(t || ':*', ' & ')) end
    from regexp_split_to_table(public.search_normalize(p_q), '[^a-z0-9]+') t
   where t <> '';
$$;

-- For LIKE: the query with its wildcards escaped.
create function public.search_like_escape(p_q text)
returns text
language sql
immutable
set search_path = ''
as $$
  select replace(replace(replace(p_q, '\', '\\'), '%', '\%'), '_', '\_');
$$;

-- ---------------------------------------------------------------------------
-- Search documents
-- ---------------------------------------------------------------------------

create table public.product_search (
  product_id uuid primary key references public.products (id) on delete cascade,
  doc tsvector not null,
  names text not null,     -- lowercased English and Khmer names
  haystack text not null,  -- names, brand and category names
  updated_at timestamptz not null default now()
);
create index product_search_doc_idx on public.product_search using gin (doc);
create index product_search_haystack_trgm_idx on public.product_search
  using gin (haystack extensions.gin_trgm_ops);

-- Shoppers read it only through the search functions; staff may look at it
-- to understand a ranking.
alter table public.product_search enable row level security;
create policy "product_search: staff read"
  on public.product_search for select to authenticated
  using ((select public.is_staff()));
revoke all on public.product_search from anon, authenticated;
grant select on public.product_search to authenticated;

-- Rebuilds the documents of p_ids from their names, brand and category path.
create function public.refresh_product_search(p_ids uuid[])
returns void
language sql
security definer
set search_path = ''
as $$
  with recursive path as (
    select p.id as product_id, c.parent_id, c.name, 0 as depth
      from public.products p
      join public.categories c on c.id = p.category_id
     where p.id = any (p_ids)
    union all
    select path.product_id, c.parent_id, c.name, path.depth + 1
      from path
      join public.categories c on c.id = path.parent_id
     where path.depth < 5
  ),
  cats as (
    select product_id,
           string_agg(coalesce(name ->> 'en', ''), ' ' order by depth) as en,
           string_agg(coalesce(name ->> 'km', ''), ' ' order by depth) as km
      from path
     group by product_id
  )
  insert into public.product_search (product_id, doc, names, haystack, updated_at)
  select p.id,
         setweight(to_tsvector('english', coalesce(p.name ->> 'en', '')), 'A')
           || setweight(to_tsvector('simple', coalesce(p.name ->> 'km', '')), 'A')
           || setweight(to_tsvector('english', coalesce(p.brand, '')), 'B')
           || setweight(to_tsvector('english', coalesce(c.en, '')), 'C')
           || setweight(to_tsvector('simple', coalesce(c.km, '')), 'C'),
         lower(concat_ws(' ', p.name ->> 'en', p.name ->> 'km')),
         lower(concat_ws(' ', p.name ->> 'en', p.name ->> 'km', p.brand, c.en, c.km)),
         now()
    from public.products p
    left join cats c on c.product_id = p.id
   where p.id = any (p_ids)
  on conflict (product_id) do update
     set doc = excluded.doc,
         names = excluded.names,
         haystack = excluded.haystack,
         updated_at = excluded.updated_at;
$$;

create function public.product_search_sync()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.refresh_product_search(array[new.id]);
  return null;
end;
$$;

create trigger product_search_sync
  after insert or update of name, brand, category_id on public.products
  for each row execute function public.product_search_sync();

-- A renamed or moved category changes the documents of every product under it.
create function public.product_search_sync_category()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.refresh_product_search(array(
    with recursive tree as (
      select new.id as id
      union all
      select c.id from public.categories c join tree t on c.parent_id = t.id
    )
    select p.id from public.products p where p.category_id in (select id from tree)
  ));
  return null;
end;
$$;

create trigger product_search_sync_category
  after update of name, parent_id on public.categories
  for each row execute function public.product_search_sync_category();

select public.refresh_product_search(array(select id from public.products));

-- ---------------------------------------------------------------------------
-- Vocabulary
-- ---------------------------------------------------------------------------

-- Words and two-word phrases of active product names, Khmer names (split on
-- spaces only, so Khmer clusters stay whole), brands and category names,
-- each with how many products use it.
create materialized view public.search_vocabulary as
with active as (
  select p.id, p.name, p.brand, p.category_id
    from public.products p
   where p.status = 'active'
),
en_words as (
  select a.id, w.words
    from active a,
         lateral (select array_remove(
                    regexp_split_to_array(lower(coalesce(a.name ->> 'en', '')), '[^[:alnum:]]+'),
                    '') as words) w
),
terms as (
  select e.id, e.words[i] as term
    from en_words e, generate_subscripts(e.words, 1) i
  union all
  select e.id, e.words[i] || ' ' || e.words[i + 1]
    from en_words e, generate_subscripts(e.words, 1) i
   where i < cardinality(e.words)
  union all
  select a.id, lower(k)
    from active a, regexp_split_to_table(btrim(coalesce(a.name ->> 'km', '')), '\s+') k
  union all
  select a.id, lower(btrim(a.brand)) from active a where a.brand is not null
  union all
  select a.id, lower(n.name)
    from active a
    join public.categories c on c.id = a.category_id
    left join public.categories pc on pc.id = c.parent_id
   cross join lateral (values (c.name ->> 'en'), (c.name ->> 'km'),
                              (pc.name ->> 'en'), (pc.name ->> 'km')) n (name)
   where n.name is not null
)
select term, count(distinct id)::int as products
  from terms
 where char_length(term) >= 2 and term !~ '^[0-9 ]+$'
 group by term;

create unique index search_vocabulary_term_idx on public.search_vocabulary (term);
create index search_vocabulary_prefix_idx on public.search_vocabulary (term text_pattern_ops);
create index search_vocabulary_trgm_idx on public.search_vocabulary
  using gin (term extensions.gin_trgm_ops);
revoke all on public.search_vocabulary from anon, authenticated;

create function public.refresh_search_vocabulary()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  refresh materialized view public.search_vocabulary;
  return null;
end;
$$;

-- Not on sold_count or ratings: those change with every order and review.
create trigger refresh_search_vocabulary
  after insert or delete or update of name, brand, status, category_id on public.products
  for each statement execute function public.refresh_search_vocabulary();
create trigger refresh_search_vocabulary
  after insert or delete or update of name, parent_id, active on public.categories
  for each statement execute function public.refresh_search_vocabulary();

-- ---------------------------------------------------------------------------
-- Matching
-- ---------------------------------------------------------------------------

-- Active products matching p_q, with a relevance score: full-text rank
-- (name > brand > category) plus how close the query is to the name, plus a
-- bonus when the name contains or starts with it.
--
-- Each way of matching is its own indexed lookup, built for this query and
-- planned with its values (EXECUTE), so the GIN indexes are used instead of
-- scoring every product.
create function public.search_matches(p_q text)
returns table (product_id uuid, relevance real)
language plpgsql
stable
security definer
set search_path = ''
set pg_trgm.word_similarity_threshold = 0.5
as $$
declare
  v_q text := public.search_normalize(p_q);
  v_tsq tsquery := public.search_tsquery(v_q);
  v_arms text[] := '{}';
  v_scored constant text := $sql$
    with hits as (%s)
    select s.product_id,
           (coalesce(ts_rank(s.doc, $2), 0)
            + extensions.word_similarity($1, s.names)
            + case when s.names like '%%' || $3 || '%%' then 0.5 else 0 end
            + case when s.names like $3 || '%%' then 0.5 else 0 end)::real
      from public.product_search s
      join public.products p on p.id = s.product_id and p.status = 'active'
     where s.product_id in (select h.product_id from hits h)
  $sql$;
begin
  if v_q = '' then
    return;
  end if;
  if v_tsq is not null then
    v_arms := v_arms || 'select s.product_id from public.product_search s where s.doc @@ $2'::text;
  end if;
  -- Short Latin queries only by prefix: "he" shouldn't find "the".
  if char_length(v_q) >= 3 or v_tsq is null then
    v_arms := v_arms || $arm$select s.product_id from public.product_search s
                              where s.haystack like '%' || $3 || '%'$arm$::text;
  end if;
  if cardinality(v_arms) > 0 then
    return query execute format(v_scored, array_to_string(v_arms, ' union '))
      using v_q, v_tsq, public.search_like_escape(v_q);
  end if;

  -- Typos only when the words themselves find nothing, and from 4
  -- characters: shorter queries have too few trigrams, and a 3-letter Khmer
  -- word would match unrelated names.
  if not found and char_length(v_q) >= 4 then
    return query execute format(v_scored,
      'select s.product_id from public.product_search s
        where $1 operator(extensions.<%) s.haystack')
      using v_q, v_tsq, public.search_like_escape(v_q);
  end if;
end;
$$;
revoke execute on function public.search_matches(text) from public;
grant execute on function public.search_matches(text) to anon, authenticated;

-- Up to p_limit vocabulary terms for C-04: those starting with the query,
-- most used first; when there are none, the closest spellings (fuzzy).
create function public.search_terms(p_q text, p_limit integer default 4)
returns table (term text, products integer, fuzzy boolean, ord integer)
language sql
stable
security definer
set search_path = ''
set pg_trgm.similarity_threshold = 0.3
as $$
  with q as (select public.search_normalize(p_q) as q),
  prefix as (
    select v.term, v.products, false as fuzzy,
           row_number() over (order by v.products desc, char_length(v.term), v.term)::int as ord
      from public.search_vocabulary v, q
     where char_length(q.q) >= 2
       and v.term like public.search_like_escape(q.q) || '%'
     order by ord
     limit least(greatest(p_limit, 1), 10)
  ),
  near as (
    select v.term, v.products, true as fuzzy,
           row_number() over (order by extensions.similarity(v.term, q.q) desc,
                                       v.products desc, v.term)::int as ord
      from public.search_vocabulary v, q
     where char_length(q.q) >= 3
       and not exists (select 1 from prefix)
       and v.term operator(extensions.%) q.q
     order by ord
     limit least(greatest(p_limit, 1), 10)
  )
  select * from prefix
  union all
  select * from near
  order by ord;
$$;
revoke execute on function public.search_terms(text, integer) from public;
grant execute on function public.search_terms(text, integer) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- catalog_browse with search
-- ---------------------------------------------------------------------------

drop function public.catalog_browse(uuid, text, text[], integer, integer, numeric, boolean, boolean, text, integer, integer);

-- As in F11, plus p_q (search) and p_sort `relevance` (Best match, the
-- default when searching). Without p_q, relevance falls back to popular.
create function public.catalog_browse(
  p_category uuid default null,
  p_collection text default null,
  p_brands text[] default null,
  p_min_cents integer default null,
  p_max_cents integer default null,
  p_min_rating numeric default null,
  p_in_stock boolean default false,
  p_same_day boolean default false,
  p_sort text default null,
  p_limit integer default 20,
  p_offset integer default 0,
  p_q text default null
)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_business boolean := public.is_business();
  v_audience text := case when public.is_business() then 'business' else 'retail' end;
  v_min integer := case when public.is_business() then null else p_min_cents end;
  v_max integer := case when public.is_business() then null else p_max_cents end;
  v_brands text[] := case when cardinality(p_brands) > 0 then p_brands end;
  v_q text := nullif(public.search_normalize(p_q), '');
  v_sort text := coalesce(p_sort, case when p_q is not null then 'relevance' else 'popular' end);
  v_collection uuid;
  v_rows jsonb;
  v_total int;
  v_brand_facets jsonb;
  v_bounds jsonb;
  v_all_same_day boolean;
begin
  if v_sort not in ('popular', 'newest', 'price_asc', 'price_desc', 'rating', 'curated', 'relevance') then
    v_sort := 'popular';
  end if;
  if v_business and v_sort in ('price_asc', 'price_desc') then
    v_sort := 'popular';
  end if;
  if v_sort = 'relevance' and v_q is null then
    v_sort := 'popular';
  end if;

  if p_collection is not null then
    select c.id into v_collection
      from public.collections c
     where c.slug = p_collection
       and c.active
       and c.audience::text in ('all', v_audience);
    if v_collection is null then
      return jsonb_build_object(
        'rows', '[]'::jsonb, 'total', 0, 'brands', '[]'::jsonb,
        'price_bounds', null, 'all_same_day', false);
    end if;
  end if;

  -- A query that is only spaces or punctuation finds nothing.
  if p_q is not null and v_q is null then
    return jsonb_build_object(
      'rows', '[]'::jsonb, 'total', 0, 'brands', '[]'::jsonb,
      'price_bounds', null, 'all_same_day', false);
  end if;

  with recursive tree as (
    select c.id from public.categories c where c.id = p_category and c.active
    union all
    select c.id from public.categories c join tree t on c.parent_id = t.id where c.active
  ),
  matches as (
    select m.product_id, m.relevance
      from public.search_matches(v_q) m
     where v_q is not null
  ),
  candidates as (
    select p.id, p.slug, p.name, p.brand, p.rating_avg, p.rating_count, p.sold_count,
           p.same_day, p.tags, p.rfq_enabled, p.rfq_min_qty, p.created_at,
           ci.sort as curated_sort,
           m.relevance
      from public.products p
      left join public.collection_items ci
        on ci.collection_id = v_collection and ci.product_id = p.id
      left join matches m on m.product_id = p.id
     where p.status = 'active'
       and (p_category is null or p.category_id in (select id from tree))
       and (v_collection is null or ci.product_id is not null)
       and (v_q is null or m.product_id is not null)
  ),
  -- Lowest price and what can be ordered, in one pass over the candidates'
  -- active variants rather than one lookup per product (F11 did that, and
  -- it took seconds at a few thousand products).
  cheapest as (
    select distinct on (v.product_id)
           v.product_id, pr.amount_cents, pr.compare_at_cents
      from public.product_variants v
      join public.prices pr on pr.variant_id = v.id
     where v.active and v.product_id in (select id from candidates)
     order by v.product_id, pr.amount_cents
  ),
  stocked as (
    select a.product_id, sum(greatest(a.available, 0)) as available
      from public.variant_availability a
      join public.product_variants v on v.id = a.variant_id
     where v.active and a.product_id in (select id from candidates)
     group by a.product_id
  ),
  base as (
    select c.*,
           ch.amount_cents as min_price,
           ch.compare_at_cents as compare_at,
           coalesce(st.available, 0) as available
      from candidates c
      left join cheapest ch on ch.product_id = c.id
      left join stocked st on st.product_id = c.id
  ),
  scoped as (
    select * from base b
     where (not coalesce(p_in_stock, false) or b.available > 0)
       and (not coalesce(p_same_day, false) or b.same_day)
       and (p_min_rating is null or b.rating_avg >= p_min_rating)
  ),
  priced as (
    select * from scoped s
     where (v_min is null or s.min_price >= v_min)
       and (v_max is null or s.min_price <= v_max)
  ),
  filtered as (
    select * from priced p
     where v_brands is null or p.brand = any (v_brands)
  )
  select
    (select count(*) from filtered),
    (select coalesce(bool_and(f.same_day), false) from filtered f),
    (select coalesce(jsonb_agg(jsonb_build_object('brand', b.brand, 'count', b.n)
                               order by b.n desc, b.brand), '[]')
       from (select p.brand, count(*) as n from priced p
              where p.brand is not null and btrim(p.brand) <> ''
              group by p.brand) b),
    (select case when v_business or count(s.min_price) = 0 then null
                 else jsonb_build_object('min', min(s.min_price), 'max', max(s.min_price)) end
       from scoped s),
    (select coalesce(jsonb_agg(page.row_data order by page.rn), '[]')
       from (
         select row_number() over (
                  order by
                    case when v_sort = 'relevance' then f.relevance end desc nulls last,
                    case when v_sort = 'curated' then f.curated_sort end asc nulls last,
                    case when v_sort = 'newest' then f.created_at end desc,
                    case when v_sort = 'price_asc' then f.min_price end asc nulls last,
                    case when v_sort = 'price_desc' then f.min_price end desc nulls last,
                    case when v_sort = 'rating' then f.rating_avg end desc,
                    case when v_sort = 'rating' then f.rating_count end desc,
                    f.sold_count desc, f.rating_count desc, f.id
                ) as rn,
                jsonb_build_object(
                  'id', f.id,
                  'slug', f.slug,
                  'name', f.name,
                  'brand', f.brand,
                  'rating_avg', f.rating_avg,
                  'rating_count', f.rating_count,
                  'sold_count', f.sold_count,
                  'same_day', f.same_day,
                  'tags', to_jsonb(f.tags),
                  'rfq_enabled', f.rfq_enabled,
                  'rfq_min_qty', f.rfq_min_qty,
                  'min_price_cents', f.min_price,
                  'compare_at_cents', f.compare_at,
                  'available', f.available,
                  'main_image', (select i.path from public.product_images i
                                  where i.product_id = f.id order by i.sort limit 1)
                ) as row_data
           from filtered f
       ) page
      where page.rn > greatest(p_offset, 0)
        and page.rn <= greatest(p_offset, 0) + least(greatest(p_limit, 1), 60))
    into v_total, v_all_same_day, v_brand_facets, v_bounds, v_rows;

  return jsonb_build_object(
    'rows', v_rows,
    'total', v_total,
    'brands', v_brand_facets,
    'price_bounds', v_bounds,
    'all_same_day', v_all_same_day and v_total > 0
  );
end;
$$;
revoke execute on function public.catalog_browse(uuid, text, text[], integer, integer, numeric, boolean, boolean, text, integer, integer, text) from public;
grant execute on function public.catalog_browse(uuid, text, text[], integer, integer, numeric, boolean, boolean, text, integer, integer, text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- C-04 suggestions
-- ---------------------------------------------------------------------------

-- {terms: [{term, fuzzy}], scope: {term, category: {id, slug, name}} | null,
--  products: [{id, name, brand, min_price_cents, category, main_image}]}
-- after 2 characters. `scope` is "headphones in Audio": the category with
-- the most matches for the first term. Runs as the caller, so business
-- buyers get no prices.
create function public.catalog_suggest(p_q text, p_limit integer default 3)
returns jsonb
language sql
stable
set search_path = ''
as $$
  with q as (select public.search_normalize(p_q) as q),
  terms as (
    select t.term, t.fuzzy, t.ord
      from q, public.search_terms(q.q, 4) t
     where char_length(q.q) >= 2
  ),
  top_term as (select term from terms order by ord limit 1),
  scope as (
    select t.term, c.id, c.slug, c.name
      from top_term t
     cross join lateral public.search_matches(t.term) m
      join public.products p on p.id = m.product_id
      join public.categories c on c.id = p.category_id and c.active
     group by t.term, c.id
     order by count(*) desc, c.sort
     limit 1
  ),
  hits as (
    select p.id, p.name, p.brand, p.category_id, m.relevance, p.sold_count
      from q
     cross join lateral public.search_matches(q.q) m
      join public.products p on p.id = m.product_id
     where char_length(q.q) >= 2
     order by m.relevance desc, p.sold_count desc, p.id
     limit least(greatest(p_limit, 0), 10)
  )
  select jsonb_build_object(
    'terms', coalesce((select jsonb_agg(jsonb_build_object('term', t.term, 'fuzzy', t.fuzzy)
                                        order by t.ord) from terms t), '[]'::jsonb),
    'scope', (select jsonb_build_object(
                       'term', s.term,
                       'category', jsonb_build_object('id', s.id, 'slug', s.slug, 'name', s.name))
                from scope s),
    'products', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', h.id,
               'name', h.name,
               'brand', h.brand,
               'min_price_cents', (select min(pr.amount_cents)
                                     from public.product_variants v
                                     join public.prices pr on pr.variant_id = v.id
                                    where v.product_id = h.id and v.active),
               'category', (select c.name from public.categories c where c.id = h.category_id),
               'main_image', (select i.path from public.product_images i
                               where i.product_id = h.id order by i.sort limit 1))
             order by h.relevance desc, h.sold_count desc, h.id)
        from hits h), '[]'::jsonb)
  );
$$;
revoke execute on function public.catalog_suggest(text, integer) from public;
grant execute on function public.catalog_suggest(text, integer) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- C-04b "Did you mean"
-- ---------------------------------------------------------------------------

-- Each word the catalog doesn't know is swapped for the closest one it
-- does (trigram similarity >= 0.3). Returns the corrected query only if
-- something changed and it finds products; null otherwise.
create function public.search_did_you_mean(p_q text)
returns text
language plpgsql
stable
security definer
set search_path = ''
set pg_trgm.similarity_threshold = 0.3
as $$
declare
  v_q text := public.search_normalize(p_q);
  v_word text;
  v_best text;
  v_out text[] := '{}';
  v_changed boolean := false;
begin
  if char_length(v_q) < 3 then
    return null;
  end if;
  foreach v_word in array regexp_split_to_array(v_q, ' ') loop
    v_best := null;
    if char_length(v_word) >= 3 and not exists (
      select 1 from public.search_vocabulary v
       where v.term like public.search_like_escape(v_word) || '%'
    ) then
      select v.term into v_best
        from public.search_vocabulary v
       where v.term operator(extensions.%) v_word
         and position(' ' in v.term) = 0
       order by extensions.similarity(v.term, v_word) desc, v.products desc, v.term
       limit 1;
    end if;
    if v_best is not null then
      v_out := v_out || v_best;
      v_changed := true;
    else
      v_out := v_out || v_word;
    end if;
  end loop;

  if not v_changed
     or not exists (select 1 from public.search_matches(array_to_string(v_out, ' '))) then
    return null;
  end if;
  return array_to_string(v_out, ' ');
end;
$$;
revoke execute on function public.search_did_you_mean(text) from public;
grant execute on function public.search_did_you_mean(text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Popular categories (C-04, C-04b)
-- ---------------------------------------------------------------------------

-- The categories whose active products sell the most, as [{id, slug, name,
-- icon, parent_id}].
create function public.popular_categories(p_limit integer default 6)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', c.id, 'slug', c.slug, 'name', c.name, 'icon', c.icon,
           'parent_id', c.parent_id, 'sort', c.sort)
         order by x.sold desc, x.n desc, c.sort), '[]'::jsonb)
    from (
      select p.category_id, sum(p.sold_count) as sold, count(*) as n
        from public.products p
       where p.status = 'active'
       group by p.category_id
       order by sold desc, n desc
       limit least(greatest(p_limit, 1), 20)
    ) x
    join public.categories c on c.id = x.category_id and c.active;
$$;
revoke execute on function public.popular_categories(integer) from public;
grant execute on function public.popular_categories(integer) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Recent searches and the search log
-- ---------------------------------------------------------------------------

create table public.search_history (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles (id) on delete cascade,
  query text not null check (char_length(query) between 1 and 100),
  searched_at timestamptz not null default now(),
  unique (profile_id, query)
);
create index search_history_recent_idx on public.search_history (profile_id, searched_at desc);

alter table public.search_history enable row level security;
create policy "search_history: own"
  on public.search_history for select to authenticated
  using (profile_id = (select auth.uid()));
create policy "search_history: clear own"
  on public.search_history for delete to authenticated
  using (profile_id = (select auth.uid()));
revoke all on public.search_history from anon, authenticated;
grant select, delete on public.search_history to authenticated;

create table public.search_log (
  id bigint generated always as identity primary key,
  profile_id uuid references public.profiles (id) on delete set null,
  query text not null,
  results integer not null,
  took_ms integer,  -- measured in the app, network included
  created_at timestamptz not null default now()
);
create index search_log_created_idx on public.search_log (created_at desc);

alter table public.search_log enable row level security;
create policy "search_log: staff read"
  on public.search_log for select to authenticated
  using ((select public.is_staff()));
revoke all on public.search_log from anon, authenticated;
grant select on public.search_log to authenticated;

-- Called by the app after each search: logs it and, for a signed-in
-- shopper, moves it to the top of their recent searches (20 kept).
create function public.record_search(p_query text, p_results integer, p_took_ms integer default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_q text := public.search_normalize(p_query);
begin
  if v_q = '' then
    return;
  end if;
  insert into public.search_log (profile_id, query, results, took_ms)
  values (v_uid, v_q, greatest(coalesce(p_results, 0), 0),
          least(greatest(p_took_ms, 0), 600000));

  if v_uid is null then
    return;
  end if;
  insert into public.search_history (profile_id, query)
  values (v_uid, v_q)
  on conflict (profile_id, query) do update set searched_at = now();
  delete from public.search_history h
   where h.profile_id = v_uid
     and h.id not in (select id from public.search_history
                       where profile_id = v_uid
                       order by searched_at desc
                       limit 20);
end;
$$;
revoke execute on function public.record_search(text, integer, integer) from public;
grant execute on function public.record_search(text, integer, integer) to anon, authenticated;

-- Trigger-only and helper functions are not callable through the API.
revoke execute on function
  public.refresh_product_search(uuid[]),
  public.product_search_sync(),
  public.product_search_sync_category(),
  public.refresh_search_vocabulary()
from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Account deletion also forgets what the shopper searched for
-- ---------------------------------------------------------------------------

create or replace function private.anonymise_account(p_uid uuid, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role public.user_role;
begin
  select role into v_role from public.profiles where id = p_uid;
  if not found or exists (
    select 1 from public.profiles where id = p_uid and deleted_at is not null
  ) then
    return;
  end if;

  delete from public.addresses where profile_id = p_uid;
  delete from public.wishlists where profile_id = p_uid;
  delete from public.carts where profile_id = p_uid;
  delete from public.conversations where customer_id = p_uid;  -- messages cascade
  delete from public.notifications where profile_id = p_uid;
  delete from public.device_tokens where profile_id = p_uid;
  delete from public.search_history where profile_id = p_uid;
  update public.search_log set profile_id = null where profile_id = p_uid;

  -- Company name, TIN and address stay: they are printed on B2B invoices.
  update public.business_profiles
     set contact_name = null, contact_phone = null, licence_path = null
   where profile_id = p_uid;

  update public.profiles
     set full_name = null,
         phone = null,
         email = null,
         avatar_url = null,
         notification_prefs = '{}',
         blocked_reason = null,
         deletion_requested_at = coalesce(deletion_requested_at, now()),
         deleted_at = now()
   where id = p_uid;

  insert into public.audit_logs (actor_id, entity, entity_id, action, diff)
  values (
    null,
    'profiles',
    p_uid::text,
    'delete',
    jsonb_build_object('role', v_role, 'reason', nullif(trim(p_reason), ''))
  );
end;
$$;
