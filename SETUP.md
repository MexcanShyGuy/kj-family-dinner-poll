# KJ's Family Dinner Poll

A separate, mobile-friendly dinner poll for KJ. It keeps the same menu as the reference poll: seared Atlantic salmon, steak frites, and cacio e pepe; mixed green salad is included. Voters must enter a name, may add a phone number, and can include allergies or substitution requests.

## Privacy design

- The public page displays aggregate meal counts only.
- Names, phone numbers, meal selections, allergies, and substitution requests are stored in a private table with direct API access revoked.
- Anonymous writes and aggregate reads go through narrow database functions. The organizer function checks an authenticated email against a private allowlist before returning any response details.
- The organizer page uses one-time email sign-in; non-allowlisted users cannot retrieve private responses.
- The public GitHub Pages repository must contain only browser-safe configuration. Never add a Supabase service-role key, database password, or private organizer data to it.
- This is a casual family poll: voter identity is not verified, so it is not tamper-proof voting.

## Separate backend setup

Use a **new Supabase project** so this poll's data stays separate from the existing dinner poll.

1. Create a Supabase project named `KJ Family Dinner Poll` on the free tier. Choose and store the database password in your password manager; do not put it in the website repository.
2. In that project's SQL Editor, run [`supabase-setup.sql`](./supabase-setup.sql).
3. Privately add each organizer email to the allowlist from the SQL Editor, replacing the sample value with the exact email:

   ```sql
   insert into public.kj_family_dinner_organizers (email)
   values (lower('ORGANIZER_EMAIL'))
   on conflict (email) do nothing;
   ```

   Never commit the real email or this private SQL result to the public site repository. Only authorized organizers should be added.
4. In Supabase Authentication URL settings, allow the deployed organizer URL ending in `/organizer.html` as a redirect URL. Set the deployed poll URL as the site URL. Keep email OTP sign-in enabled.
5. Copy the project's **Project URL** and **publishable key** (or legacy `anon` public key) into the two configuration constants in both `index.html` and `organizer.html`. These are browser-safe keys. Never use the `service_role` key.
6. Commit the configured HTML files to the public Pages repository and enable GitHub Pages from `main` at `/`.

## Smoke test

1. Open the public poll over HTTPS; verify the three choices and included salad.
2. Submit a test response with a name, a phone number, one meal, and a sample dietary note.
3. Verify only the aggregate count is visible on the public poll.
4. Sign in at `/organizer.html` with an allowlisted email and verify the private response fields appear.
5. Test a non-allowlisted account; the private RPC must deny access.
6. Remove the test response from the private Supabase dashboard after verification.

Restaurant substitutions and cross-contact safety must be confirmed with the restaurant; the poll does not claim any substitute is approved.
