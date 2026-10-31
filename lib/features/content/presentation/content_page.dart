import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/ui/k_ui.dart';
import '../../admin/presentation/admin_shell.dart';
import '../../catalog/data/file_pick.dart';
import '../../catalog/domain/i18n_text.dart';
import '../data/content_repository.dart';
import '../domain/content.dart';

final adminBannersProvider = FutureProvider(
  (ref) => ref.watch(contentRepositoryProvider).banners(),
);
final adminCollectionsProvider = FutureProvider(
  (ref) => ref.watch(contentRepositoryProvider).collections(),
);
final contentPagesProvider = FutureProvider(
  (ref) => ref.watch(contentRepositoryProvider).pages(),
);

class ContentAdminPage extends ConsumerWidget {
  const ContentAdminPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return DefaultTabController(
      length: 3,
      child: AdminPage(
        title: l.adminSectionContent,
        showBack: true,
        actions: [
          KButton(
            icon: KIcons.plus,
            label: l.contentNewBanner,
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const BannerEditorDialog(),
            ),
          ),
        ],
        children: [
          TabBar(
            tabs: [
              Tab(text: l.contentBanners),
              Tab(text: l.contentCollections),
              Tab(text: l.contentPages),
            ],
          ),
          SizedBox(
            height: 520,
            child: TabBarView(
              children: [
                _BannerList(value: ref.watch(adminBannersProvider)),
                _CollectionList(value: ref.watch(adminCollectionsProvider)),
                _PageList(value: ref.watch(contentPagesProvider)),
              ],
            ),
          ),
          KBanner(message: l.contentInfo, icon: KIcons.info),
        ],
      ),
    );
  }
}

class _LoadView<T> extends StatelessWidget {
  const _LoadView({required this.value, required this.builder});
  final AsyncValue<List<T>> value;
  final Widget Function(List<T>) builder;
  @override
  Widget build(BuildContext context) => value.when(
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (e, _) => Center(
      child: KEmptyState(
        icon: KIcons.warning,
        title: AppLocalizations.of(context).contentSaveFailed,
        message: '$e',
      ),
    ),
    data: builder,
  );
}

class _BannerList extends StatelessWidget {
  const _BannerList({required this.value});
  final AsyncValue<List<AdminBanner>> value;
  @override
  Widget build(BuildContext context) => _LoadView(
    value: value,
    builder: (rows) {
      final l = AppLocalizations.of(context);
      if (rows.isEmpty) return Center(child: Text(l.contentEmpty));
      return ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: rows.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final b = rows[i];
          return ListTile(
            minVerticalPadding: 12,
            leading: CircleAvatar(child: Text('${b.sort}')),
            title: Text(
              b.title.of(Localizations.localeOf(context).languageCode),
            ),
            subtitle: Text(
              '${_audience(l, b.audience)} · ${_state(l, b.stateAt(DateTime.now()))} · ${_schedule(l, b)}',
            ),
            trailing: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => BannerEditorDialog(initial: b),
              ),
              child: Text(l.contentEdit),
            ),
          );
        },
      );
    },
  );
}

class _CollectionList extends ConsumerWidget {
  const _CollectionList({required this.value});
  final AsyncValue<List<AdminCollection>> value;
  @override
  Widget build(BuildContext context, WidgetRef ref) => _LoadView(
    value: value,
    builder: (rows) {
      final l = AppLocalizations.of(context);
      return ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: rows.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final c = rows[i];
          return SwitchListTile(
            value: c.active,
            title: Text(
              c.title.of(Localizations.localeOf(context).languageCode),
            ),
            subtitle: Text('${c.slug} · ${_audience(l, c.audience)}'),
            secondary: IconButton(
              tooltip: l.contentEdit,
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => _CollectionEditor(initial: c),
              ),
            ),
            onChanged: (active) async {
              await ref
                  .read(contentRepositoryProvider)
                  .saveCollection(
                    AdminCollection(
                      id: c.id,
                      slug: c.slug,
                      title: c.title,
                      audience: c.audience,
                      active: active,
                      sort: c.sort,
                    ),
                  );
              ref.invalidate(adminCollectionsProvider);
            },
          );
        },
      );
    },
  );
}

class _CollectionEditor extends ConsumerStatefulWidget {
  const _CollectionEditor({required this.initial});
  final AdminCollection initial;
  @override
  ConsumerState<_CollectionEditor> createState() => _CollectionEditorState();
}

class _CollectionEditorState extends ConsumerState<_CollectionEditor> {
  late final en = TextEditingController(text: widget.initial.title.en);
  late final km = TextEditingController(text: widget.initial.title.km);
  late ContentAudience audience = widget.initial.audience;
  late bool active = widget.initial.active;

  @override
  void dispose() {
    en.dispose();
    km.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.initial.slug),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: en,
              decoration: InputDecoration(labelText: l.contentTitleEnglish),
            ),
            TextField(
              controller: km,
              decoration: InputDecoration(labelText: l.contentTitleKhmer),
            ),
            DropdownButtonFormField(
              initialValue: audience,
              decoration: InputDecoration(labelText: l.contentAudience),
              items: [
                for (final value in ContentAudience.values)
                  DropdownMenuItem(
                    value: value,
                    child: Text(_audience(l, value)),
                  ),
              ],
              onChanged: (value) => setState(() => audience = value!),
            ),
            SwitchListTile(
              value: active,
              title: Text(l.contentActive),
              onChanged: (value) => setState(() => active = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        TextButton(
          onPressed: () async {
            await ref
                .read(contentRepositoryProvider)
                .saveCollection(
                  AdminCollection(
                    id: widget.initial.id,
                    slug: widget.initial.slug,
                    title: I18nText(en: en.text, km: km.text),
                    audience: audience,
                    active: active,
                    sort: widget.initial.sort,
                  ),
                );
            ref.invalidate(adminCollectionsProvider);
            if (context.mounted) Navigator.pop(context);
          },
          child: Text(l.contentSaved),
        ),
      ],
    );
  }
}

class _PageList extends ConsumerWidget {
  const _PageList({required this.value});
  final AsyncValue<List<ContentPageModel>> value;
  @override
  Widget build(BuildContext context, WidgetRef ref) => _LoadView(
    value: value,
    builder: (rows) {
      final l = AppLocalizations.of(context);
      return ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: rows.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final p = rows[i];
          return ListTile(
            title: Text(
              p.title.of(Localizations.localeOf(context).languageCode),
            ),
            subtitle: Text(
              '${p.slug} · ${p.published ? l.contentPublished : l.contentDraft}',
            ),
            trailing: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => _PageEditor(initial: p),
              ),
              child: Text(l.contentEdit),
            ),
          );
        },
      );
    },
  );
}

class BannerEditorDialog extends ConsumerStatefulWidget {
  const BannerEditorDialog({super.key, this.initial});
  final AdminBanner? initial;
  @override
  ConsumerState<BannerEditorDialog> createState() => _BannerEditorState();
}

class _BannerEditorState extends ConsumerState<BannerEditorDialog> {
  final form = GlobalKey<FormState>();
  late final titleEn = TextEditingController(text: widget.initial?.title.en);
  late final titleKm = TextEditingController(text: widget.initial?.title.km);
  late final subtitle = TextEditingController(
    text: widget.initial?.subtitle.en,
  );
  late final cta = TextEditingController(text: widget.initial?.cta.en);
  late final target = TextEditingController(text: widget.initial?.linkTarget);
  late ContentAudience audience =
      widget.initial?.audience ?? ContentAudience.all;
  late String linkType = widget.initial?.linkType ?? 'collection';
  late bool active = widget.initial?.active ?? true;
  late DateTime? starts = widget.initial?.startsAt;
  late DateTime? ends = widget.initial?.endsAt;
  String? imagePath;
  bool saving = false;

  @override
  void dispose() {
    titleEn.dispose();
    titleKm.dispose();
    subtitle.dispose();
    cta.dispose();
    target.dispose();
    super.dispose();
  }

  Future<DateTime?> pickDate(DateTime? current) async {
    final d = await showDatePicker(
      context: context,
      initialDate: current?.toLocal() ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (d == null || !mounted) return null;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current?.toLocal() ?? DateTime.now()),
    );
    return t == null
        ? null
        : DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  Future<void> chooseImage() async {
    final files = await ref.read(pickFilesProvider)(
      extensions: const ['jpg', 'jpeg', 'png', 'webp'],
      multiple: false,
    );
    if (files.isEmpty) return;
    setState(() => saving = true);
    try {
      imagePath = await ref
          .read(contentRepositoryProvider)
          .uploadBanner(files.first.name, files.first.bytes);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> save() async {
    if (!form.currentState!.validate() ||
        (starts != null && ends != null && !ends!.isAfter(starts!))) {
      return;
    }
    setState(() => saving = true);
    final old = widget.initial;
    try {
      await ref
          .read(contentRepositoryProvider)
          .saveBanner(
            AdminBanner(
              id: old?.id ?? '',
              title: I18nText(en: titleEn.text, km: titleKm.text),
              subtitle: I18nText(en: subtitle.text),
              cta: I18nText(en: cta.text),
              imagePath: imagePath ?? old?.imagePath,
              linkType: linkType,
              linkTarget: target.text.trim().isEmpty
                  ? null
                  : target.text.trim(),
              audience: audience,
              startsAt: starts,
              endsAt: ends,
              active: active,
              sort: old?.sort ?? 999,
            ),
          );
      ref.invalidate(adminBannersProvider);
      if (mounted) {
        Navigator.pop(context);
        showKToast(context, message: AppLocalizations.of(context).contentSaved);
      }
    } catch (_) {
      if (mounted) {
        showKToast(
          context,
          message: AppLocalizations.of(context).contentSaveFailed,
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final k = context.k;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: form,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.initial == null
                        ? l.contentNewBanner
                        : l.contentEditBanner,
                    style: k.text.h2,
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 24,
                    runSpacing: 20,
                    children: [
                      SizedBox(
                        width: 420,
                        child: Column(
                          children: [
                            TextFormField(
                              controller: titleEn,
                              decoration: InputDecoration(
                                labelText: l.contentTitleEnglish,
                              ),
                              maxLength: 32,
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? l.fieldRequired
                                  : null,
                              onChanged: (_) => setState(() {}),
                            ),
                            TextFormField(
                              controller: titleKm,
                              decoration: InputDecoration(
                                labelText: l.contentTitleKhmer,
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                            TextFormField(
                              controller: subtitle,
                              decoration: InputDecoration(
                                labelText: l.contentSubtitleEnglish,
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                            TextFormField(
                              controller: cta,
                              decoration: InputDecoration(
                                labelText: l.contentButtonEnglish,
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                            DropdownButtonFormField(
                              initialValue: audience,
                              decoration: InputDecoration(
                                labelText: l.contentAudience,
                              ),
                              items: [
                                for (final a in ContentAudience.values)
                                  DropdownMenuItem(
                                    value: a,
                                    child: Text(_audience(l, a)),
                                  ),
                              ],
                              onChanged: (v) => setState(() => audience = v!),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField(
                              initialValue: linkType,
                              decoration: InputDecoration(
                                labelText: l.contentLinkType,
                              ),
                              items: [
                                for (final v in [
                                  'collection',
                                  'category',
                                  'product',
                                  'page',
                                  'url',
                                ])
                                  DropdownMenuItem(value: v, child: Text(v)),
                              ],
                              onChanged: (v) => setState(() => linkType = v!),
                            ),
                            TextFormField(
                              controller: target,
                              decoration: InputDecoration(
                                labelText: l.contentLinkTarget,
                              ),
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: TextButton(
                                    onPressed: () async {
                                      final v = await pickDate(starts);
                                      if (v != null) setState(() => starts = v);
                                    },
                                    child: Text(
                                      '${l.contentStart}: ${starts?.toLocal().toString().substring(0, 16) ?? '—'}',
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: TextButton(
                                    onPressed: () async {
                                      final v = await pickDate(ends);
                                      if (v != null) setState(() => ends = v);
                                    },
                                    child: Text(
                                      '${l.contentEnd}: ${ends?.toLocal().toString().substring(0, 16) ?? '—'}',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              value: active,
                              title: Text(l.contentShowHome),
                              onChanged: (v) => setState(() => active = v),
                            ),
                            KButton.outline(
                              label: l.contentUploadImage,
                              onPressed: saving ? null : chooseImage,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 300,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l.contentPreviewPhone),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: k.colors.primary,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    titleEn.text.isEmpty
                                        ? l.contentTitleEnglish
                                        : titleEn.text,
                                    style: k.text.h2.copyWith(
                                      color: Colors.white,
                                    ),
                                  ),
                                  if (subtitle.text.isNotEmpty)
                                    Text(
                                      subtitle.text,
                                      style: k.text.small.copyWith(
                                        color: Colors.white,
                                      ),
                                    ),
                                  if (cta.text.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: Text(
                                        cta.text,
                                        style: k.text.small.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: saving ? null : () => Navigator.pop(context),
                        child: Text(
                          MaterialLocalizations.of(context).cancelButtonLabel,
                        ),
                      ),
                      const SizedBox(width: 8),
                      KButton(
                        label: l.contentSaveBanner,
                        loading: saving,
                        onPressed: saving ? null : save,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PageEditor extends ConsumerStatefulWidget {
  const _PageEditor({required this.initial});
  final ContentPageModel initial;
  @override
  ConsumerState<_PageEditor> createState() => _PageEditorState();
}

class _PageEditorState extends ConsumerState<_PageEditor> {
  late final en = TextEditingController(text: widget.initial.body.en),
      km = TextEditingController(text: widget.initial.body.km);
  late bool published = widget.initial.published;
  @override
  void dispose() {
    en.dispose();
    km.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.initial.title.en),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: en,
              maxLines: 6,
              decoration: InputDecoration(labelText: l.contentBodyEnglish),
            ),
            TextField(
              controller: km,
              maxLines: 6,
              decoration: InputDecoration(labelText: l.contentBodyKhmer),
            ),
            SwitchListTile(
              value: published,
              title: Text(l.contentPublished),
              onChanged: (v) => setState(() => published = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        TextButton(
          onPressed: () async {
            await ref
                .read(contentRepositoryProvider)
                .savePage(
                  ContentPageModel(
                    id: widget.initial.id,
                    slug: widget.initial.slug,
                    title: widget.initial.title,
                    body: I18nText(en: en.text, km: km.text),
                    published: published,
                  ),
                );
            ref.invalidate(contentPagesProvider);
            if (context.mounted) Navigator.pop(context);
          },
          child: Text(l.contentSaved),
        ),
      ],
    );
  }
}

String _audience(AppLocalizations l, ContentAudience a) => switch (a) {
  ContentAudience.all => l.contentAudienceAll,
  ContentAudience.retail => l.contentAudienceRetail,
  ContentAudience.business => l.contentAudienceBusiness,
};
String _state(AppLocalizations l, BannerState s) => switch (s) {
  BannerState.live => l.contentLive,
  BannerState.scheduled => l.contentScheduled,
  BannerState.ended => l.contentEnded,
  BannerState.hidden => l.contentHidden,
};
String _schedule(AppLocalizations l, AdminBanner b) =>
    b.startsAt == null && b.endsAt == null
    ? l.contentActive
    : '${b.startsAt?.toLocal().toString().substring(0, 10) ?? '…'} – ${b.endsAt?.toLocal().toString().substring(0, 10) ?? '…'}';
