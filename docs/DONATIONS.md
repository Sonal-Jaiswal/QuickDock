# Donations

QuickDock accepts voluntary donations through **GitHub Sponsors**:
<https://github.com/sponsors/Sonal-Jaiswal>

Where it appears:
- the website's Support section (`website/src/config/site.ts` → `donation`)
- the **Sponsor** button on the GitHub repository (`.github/FUNDING.yml`)
- **Support QuickDock** in the app's About screen (`DONATION_URL` in `config/release.env`, and `QD_DONATION_URL` in `project.yml`)

Leave any of these empty to hide that link. Never put a placeholder or unverified URL in them.

## Rules
- Donations are voluntary. They don't buy a licence, subscription or guaranteed feature, and the wording must say so.
- Never publish bank account numbers, UPI IDs or IFSC codes on the website or in the repository. Payouts go through the provider.
- Only set `raisedUSD` from the GitHub Sponsors dashboard, with `raisedAsOf` set to the date you checked. `null` hides the total.

## Notes for a maintainer in India
These are not tax advice. Check the current rules with a chartered accountant.
- GitHub Sponsors pays out to a bank account through Stripe Connect, in INR. Keep the payout bank details and tax form up to date in the Sponsors dashboard.
- Incoming foreign payments are received as export of services. Your bank may ask for a purpose code or a FIRC/e-FIRA (foreign inward remittance certificate) for each payout. Keep these for income tax filing.
- Sponsorship income is taxable income. If you later sell a paid version, GST and invoicing rules may apply.

## Adding another provider later
Ko-fi, Buy Me a Coffee, Razorpay Payment Pages (good for Indian UPI/cards) or Lemon Squeezy and Gumroad (for paid or pay-what-you-want sales) can be added. Point `donation.url` at the one you want the website button to use, and add extra entries to `.github/FUNDING.yml` (for example `ko_fi: your-page` or `custom: ["https://…"]`).
