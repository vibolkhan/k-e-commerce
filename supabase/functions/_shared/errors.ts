// Errors a flow throws for a malformed or unauthenticated request; the HTTP
// wrapper maps them to 400 and 401.

export class BadRequest extends Error {}

export class Unauthorized extends Error {}
