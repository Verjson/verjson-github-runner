---
date: 2026-07-29
id: 79e18e9
title: Correct what the lane-label docs claim this image enforces
summary: The lane-label documentation now states the isolated-runner enforcement boundary explicitly rather than overstating it in three ways that would each have misled an operator provisioning an isolated runner. It names `untrusted-pr` as the trigger for the contract check rather than one of three interchangeable required labels, scopes the check to supervisor mode instead of claiming it runs at admission, and drops the claim that every runner carries exactly one lane. `SECURITY.md` also loses the provider name from its isolated-admission heading, and `verjson cloud runner <lane>` is disambiguated from the provider host bullets beneath it.
---

The lane-label section added earlier today overstated the code in three ways, each of which
would have misled an operator provisioning an isolated runner. It said the three `isolated`
companion labels were interchangeably required and that dropping any one fails closed;
`untrusted-pr` is actually the *trigger* (`entrypoint.sh:125` returns success immediately
without it), so dropping that one label silently skips the entire contract check. It said
the labels are "enforced at admission", when the check runs only in supervisor mode and
never on the ordinary registration path, and covers the runner group, image digest, socket,
child network, and metadata attestation as well as labels. And it claimed every runner
carries exactly one lane, while this repo's own defaults (`entrypoint.sh:380`, `setup.sh:33`)
carry none.

The section now states the enforcement boundary explicitly instead. Also de-providers the
`Isolated GCP admission` heading in `SECURITY.md` and the test 24 names, which the earlier
change left provider-coupled, and disambiguates `verjson cloud runner <lane>` from the
GCP/DigitalOcean host bullets under it — with the new section declaring providers are never
lanes, one document was using "lane" both ways.

Follow-up to #97; still part of #80.
