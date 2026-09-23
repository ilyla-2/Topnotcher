# Windows signing acquisition — current project state

CELE Topnotcher OS currently has **no Windows code-signing certificate and no signing provider configured**.

Do not purchase or configure anything merely to make a CI checkbox green. The certificate/service must be appropriate for the actual release owner and must issue a Windows-trusted Authenticode signature.

When selecting a signing route later, record:

- provider/service name;
- whether the signer is an individual or organization identity;
- exact certificate/signing subject;
- hardware/cloud/private-key custody model;
- timestamp mechanism;
- expiration/renewal date;
- CI integration method, if any.

The final release workflow should consume secrets from the CI secret store or provider client. No signing secret belongs in the repository.

Until that is done:

- development builds may remain unsigned;
- release-candidate testing may remain unsigned;
- public release remains blocked;
- `codeSigning` remains `PENDING`;
- `releaseReady` remains `false`.
