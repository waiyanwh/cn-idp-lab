apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-signed-local-images
  annotations:
    policies.kyverno.io/title: Verify Signed Local Images
    policies.kyverno.io/category: Software Supply Chain Security
    policies.kyverno.io/severity: high
    policies.kyverno.io/description: Audit local IDP app images against the generated Cosign public key.
spec:
  validationFailureAction: Audit
  webhookTimeoutSeconds: 30
  background: false
  rules:
    - name: verify-local-idp-images
      match:
        any:
          - resources:
              kinds:
                - Pod
              namespaces:
                - apps
      verifyImages:
        - imageReferences:
            - "registry.kube-system.svc.cluster.local:5001/idp/*"
          attestors:
            - entries:
                - keys:
                    publicKeys: |-
__COSIGN_PUBLIC_KEY__
          required: true
          mutateDigest: false
          verifyDigest: false
