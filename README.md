# Pre-req
* Read [k8s-deploy-helper](https://github.com/lifechurch/k8s-deploy-helper) documentation and complete the pre-requisites.

# Getting Started
* Use GitLab to import this project from GitHub, give it a new name.
* Clone your new repo locally.
* Edit .gitlab-ci.yml and change KUBE_DOMAIN to be a unique domain name that is pointed to your Kubernetes ingress controller.
* Change the port values in the manifests to reflect the ports you want to run.
* Done! This should give you basic CI/CD pipeline with review app and canary functionality.

# Variables used in our sample manifests
* $CI_ENVIRONMENT_SLUG - "A simplified version of the environment name, suitable for inclusion in DNS, URLs, Kubernetes labels, etc." - Comes from ```environment:name``` in GitLab CI file.
* $KUBE_NAMESPACE - This variable comes from the GitLab Kubernetes Integration that you setup under Operations->Kubernetes
* $CI_JOB_ID - "The unique id of the current job that GitLab CI uses internally"
* $CI_REGISTRY_IMAGE - "If the Container Registry is enabled for the project it returns the address of the registry tied to the specific project"
* $CI_COMMIT_SHA - "The commit revision for which project is built"
* $CI_ENVIRONMENT_HOSTNAME - A custom variable we assemble that strips the http:// or https:// from CI_ENVIRONMENT_URL. CI_ENVIRONMENT_URL comes from ```environment:url``` in the GitLab CI file.

# Standard template manifest conventions

## Deployment

### name: app-$CI_ENVIRONMENT_SLUG

We use ```app-$CI_ENVIRONMENT_SLUG``` as the name of our deployment. We prefix it with ```app-``` so that if you add another deployment in, you can do something like replace ```app-$CI_ENVIRONMENT_SLUG``` with ```worker-$CI_ENVIRONMENT_SLUG``` in your new manifests.

**$CI_ENVIRONMENT_SLUG is the key to success in templating.** When manifests are deployed, it evaluates to something like ```app-staging``` or ```app-production```, depending on the GitLab CI stage you are deploying in. This allows you to have one manifest for all stages of your deployment without having to maintain 3-4 different manifests and also makes it possible for our review app functionality to work.

### Label: app: $CI_ENVIRONMENT_SLUG
We use this because this is the convention GitLab looks for in order to allow you to connect to running pods from within GitLab. This is an important label to change with caution, as not only will it break the GitLab functionality, but we also use this label as what we match our service onto. We use this label rather than name to support automatic canary creation, as we have to dynamically change the name in order to isolate canary deployments.

### Label: track: stable
We use this label because this is the convention GitLab looks for in order to identify a canary deployment in the UI. This label should only be specific deployments that you want k8s-deploy-helper to automatically create canary deployments for.

### Annotation: build_id: "$CI_JOB_ID"
We use this annotation to force pods to restart every time a job is run. This allows developers to change a secret in GitLab and re-deploy. Because Kubernetes treats annotation changes as important, pods will restart and use the new secret values.

### image: $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
By using $CI_COMMIT_SHA as our tag name, we generate a unique container for each commit. This allows for easy rollback of deployments from within the GitLab UI.

### {{SECRETS}}
This special command loops through all the secrets that k8s-deploy-helper created Kubernetes secrets for and inserts them into the manifest during template rendering. Please see the [k8s-deploy-helper repo](https://github.com/lifechurch/k8s-deploy-helper) for more information on secret creation.

### imagePullSecrets:
We create an imagePullSecret named gitlab-registry automatically as part of the deployment process.

## Service
We use a ClusterIP service in our example. The most important thing is that we use a selector like:

```
  selector:
    app: $CI_ENVIRONMENT_SLUG
```

We select on this label rather than the name because it's a label that will be the same for both production and canary builds. You can use any label you like to be the selector, just make sure you don't select on the name of the deployment.

## Ingress
The only thing you need to know in this file is $CI_ENVIRONMENT_HOSTNAME, which is used to supply which hostname a particular deployment should be accessible by via the ingress controller.

This variable comes from .gitlab-ci.yml file from the ```environment:url``` like so:

```
  environment:
    name: staging
    url: http://staging.$KUBE_DOMAIN
```

In our .gitlab-ci.yml file, $KUBE_DOMAIN is declared at the top. This CI assumes that all stages will be deployed to the same base domain. If this is not the case, feel free to hardcode the URL you want into the file.

## Autoscaling
We put the autoscaling manifest in the production folder to give an example of stage-specific manifests. In your hpa, you probably want to specifically target the name of the deployment. This will make sure it won't get applied to canary builds.

```
  scaleTargetRef:
    apiVersion: apps/v1beta1
    kind: Deployment
    name: app-$CI_ENVIRONMENT_SLUG
```

# Go code
If you end up using this example repo as-is, you may give it another name other than example-go. If you do that, make sure to change the name of the command you're running in the Dockerfile to be the name of the repo you created. For example, if your repo is called testing, change ```CMD ["/app/example-go"]``` to ```CMD ["/app/testing"]```. This is Go specific and has nothing to do with k8s-deploy-helper.














