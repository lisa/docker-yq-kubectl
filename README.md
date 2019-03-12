# docker-yq-kubectl

This is designed to be an [init container](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/) to populate various files for later use in containers.

The operations are related to writing cluster ID, AWS region name, and AWS API credentials to various files.

## Background and Requirements

Due to Kubernetes limitations, [ConfigMaps](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/) can't be used (as volumes) across namespaces. Cluster information resides in the `kube-system` namespace (or sometimes `kube-public`) and on OpenShift Dedicated, the `kube-system/configmap/cluster-config-v1` ConfigMap has two pieces of information that we'd like to access, the cluster's ID and the AWS region in which it runs.

An additional complication is the `kube-system/configmap/cluster-config-v1` is deprecated and thus we must find a different avenue for the pieces of data we care about. In the interim, we can rely on the `Machine` object(s) from the `openshift-machine-api` namespace.

There is a further desire to rely on the [cloud-credential-operator](https://github.com/openshift/cloud-credential-operator) to request AWS credentials at runtime.

### Accessing Cluster Information

To get access to the cluster information ConfigMap and other objects we could change our main container to access this information, but those initialization tasks are best suited to init containers. To that end, the [ServiceAccount](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/) for the Pod must be granted access to the aforementioned objects by [ClusterRole and RoleBinding](https://kubernetes.io/docs/reference/access-authn-authz/rbac/). A sample one follows:

```yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: pod-sa
  namespace: deployment-ns
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: access-machine-info-cr
rules:
- apiGroups: ["machine.openshift.io"]
  resources: ["machines"]
  verbs: ["get", "list"]
---
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: allow-deploy-access-to-machine-info
  namespace: openshift-machine-api
subjects:
- kind: ServiceAccount
  name: pod-sa
  namespace: deployment-ns
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: access-machine-info-cr
```

### AWS Credentials

The [cloud-credential-operator](https://github.com/openshift/cloud-credential-operator) creates a Secret in the specified namespace that has two keys, `aws_secret_access_key` and `aws_access_key_id`, each for the purpose one would expect. Most consumers of those credentials will want them in an ini-file format, and so this init container will handle that as well.

An example request for credentials looks like this:

```yaml
apiVersion: cloudcredential.openshift.io/v1beta1
kind: CredentialsRequest
metadata:
  name: deployment-aws-credentials
  namespace: openshift-monitoring
spec:
  secretRef:
    name: my-credentials-secret
    namespace: openshift-monitoring
  providerSpec:
    apiVersion: cloudcredential.openshift.io/v1beta1
    kind: AWSProviderSpec
    statementEntries:
    - effect: Allow
      action:
      - cloudwatch:ListMetrics
      - cloudwatch:GetMetricData
      resource: "*"
```

## Usage

An example deployment might look like this

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-deploy
  namespace: deployment-ns
spec:
  selector:
    matchLabels:
      app: test-deploy
spec:
  selector:
    matchLabels:
      app: test-deploy
  template:
    metadata:
      labels:
        app: test-deploy
    spec:
      serviceAccountName: pod-sa
      initContainers:
      - name: setupcreds
        image: quay.io/lseelye/yq-kubectl:stable
        command: [ "/usr/local/bin/init.py", "-r", "/secrets/aws/config.ini", "-a", "/rawsecrets/aws_access_key_id", "-A", "/rawsecrets/aws_secret_access_key", "-o", "/secrets/aws/credentials.ini" ]
        volumeMounts:
        - name: awsrawcreds
          mountPath: /rawsecrets
          readOnly: true
        - name: secrets
          mountPath: /secrets
        - name: envfiles
          mountPath: /config
      containers:
      - name: main
        image: ubuntu:18.04
        command: [ "/bin/sleep", "86400" ]
        volumeMounts:
        - name: secrets
          mountPath: /secrets
          readOnly: true
        - name: envfiles
          mountPath: /config
          readOnly: true
      volumes:
      - name: awsrawcreds
        secret:
          secretName: my-credentials-secret
      - name: secrets
        emptyDir: {}
      - name: envfiles
        emptyDir: {}
```

Once the `main` container runs, it will have the AWS configuration (`config.ini` and `credentials.ini`) populated with information from the configmap and secret. Additional usage is to write the cluster ID to a file, which the `main` container will need to `source` as part of its command, to expose `CLUSTERID` as an environment variable, if so desired.
