# Example CI/CD Pipeline for k8s-deploy-helper in Go

## Pre-req
* k8s-deploy-helper [setup steps](https://github.com/lifechurch/k8s-deploy-helper#prerequisites) completed for the GitLab Runner and the Kubernetes integration in your project.

## Getting Started
* Use GitLab to import this project from GitHub, give it a new name.
* Clone your new repo locally.
* Edit .gitlab-ci.yml and change KUBE_DOMAIN to be a unique domain name that is pointed to your Kubernetes ingress controller.
* Add a GitLab CI/CD Secret named PORT whose value is the port your web app listens on inside the container. For this demo, PORT should be set to 5555.
* Done! This should give you basic CI/CD pipeline with review app functionality.

## Narrative Explanation for those who want a deeper dive
Lets start with our .gitlab-ci.yml file and go step by step.

```image: quay.io/lifechurch/k8s-deploy-helper:1.0.0```
This sets the default image for every build stage.  If you specify an image in a build stage, GitLab will use that instead. Be sure to check out the [k8s-deploy-helper repo](https://github.com/lifechurch/k8s-deploy-helper) for new releases.

```
variables:
  BINARY_NAME: $CI_PROJECT_NAME
  KUBE_DOMAIN: myapp.com
```

This sets global variables in the project.
```BINARY_NAME``` is used as a generic way to determine what your binary is going to be called. By default, it uses your project name. You can override that here as necessary.

```KUBE_DOMAIN``` is used to indicate the base domain that is servicing all your build stages.


```
.prep_go: &prep_go
  before_script:
    - export GL_URL=$(echo $CI_PROJECT_URL | awk -F/ '{print $3}')
    - export GO_PROJECT_PATH="$GOPATH/src/$GL_URL/$CI_PROJECT_NAMESPACE"
    - mkdir -p $GO_PROJECT_PATH
    - ln -s $(pwd) $GO_PROJECT_PATH
    - export GO_PROJECT_PATH="$GO_PROJECT_PATH/$CI_PROJECT_NAME"
    - cd $GO_PROJECT_PATH
```
This section is a bunch of shell commands that we run in order to get the Go compilation environment setup. Most important to note is that it is assuming you are using this GitLab instance as your src host in GO_PATH. This is setup a section that other stages can call to setup Go as needed.

```
stages:
  - build
  - dockerbuild
  - review
  - staging
  - production
  - taglatest
```
This outlines the basic workflow of this pipeline. The process starts by committing code to a branch. We start with building the Go project in the build stage and saving the compiled artifacts in GitLab. In the dockerbuild stage, we build a container using those artifacts. In the review stage, we create a deployment in Kubernetes just for the current branch. Once the branch is merged into master and deleted, we delete the review-app deployment and the pipeline will start again at the beginning, but for the master branch.

For the master branch, we will compile the Go code again in build, followed by building the Docker container in the dockerbuild stage. This time, it will skip the review stage, and deploy your master branch out as staging. When you want to deploy to production, just go to CI/CD->Pipelines and click the big play button to deploy out to production. Once it deploys to production, it will tag the docker image it just deployed with the latest tag.

```
go_build:
  <<: *prep_go
  stage: build
  image: golang:1.9
  script:
    - go get github.com/golang/dep/cmd/dep
    - dep ensure
    - mkdir build
    - CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o build/$BINARY_NAME ./...
  artifacts:
    paths:
      - build/
    expire_in: 1 week
```
In this stage, we use the official golang image on Dockerhub to install dep to manage dependencies, grab the vendor dependencies your app has, compile it, and move the artifacts from that compilation into GitLab.

```
docker_build:
  stage: dockerbuild
  script:
    - command build
  only:
    - branches
```

In this stage, we use [k8s-deploy-helper's](https://github.com/lifechurch/k8s-deploy-helper) build helper to build your container using the instructions that are in the Dockerfile at the root of the project. When building the container, we use the container tagged with latest as the --cache-from source. The docker container that we build is tagged with the commit sha ($CI_COMMIT_SHA) and pushed to the internal Docker registry in GitLab. Using this $CI_COMMIT_SHA gives us a unique container name each time.

### k8s-deploy-helper Kubernetes Manifest Files
For the next stages: review, staging and production, it will be helpful to shift from the GitLab CI file into the manifest files in the kubernetes directory.

First, lets take a look at the deployment.yaml file
```
---
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: $CI_ENVIRONMENT_SLUG
  namespace: $KUBE_NAMESPACE
  labels:
    app: $CI_ENVIRONMENT_SLUG
    pipeline_id: "$CI_PIPELINE_ID"
    build_id: "$CI_JOB_ID"
spec:
  selector:
    matchLabels:
      app: $CI_ENVIRONMENT_SLUG
      name: $CI_ENVIRONMENT_SLUG
  template:
    metadata:
      labels:
        name: $CI_ENVIRONMENT_SLUG
        app: $CI_ENVIRONMENT_SLUG
    spec:
      terminationGracePeriodSeconds: 60
      containers:
      - name: $KUBE_NAMESPACE-$CI_ENVIRONMENT_SLUG
        image: $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
        imagePullPolicy: IfNotPresent
        ports:
          - containerPort: $PORT
        resources:
          limits:
            cpu: "1"
            memory: "128Mi"
        readinessProbe:
          httpGet:
            path: /healthz
            port: $PORT
            scheme: HTTP
            httpHeaders:
              - name: Host
                value: 127.0.0.1
          initialDelaySeconds: 5
          timeoutSeconds: 2
          periodSeconds: 3
          failureThreshold: 10
        #env:
        #  - name: SUPERSECRETTHING
        #    valueFrom:
        #      secretKeyRef:
        #        name: $KUBE_NAMESPACE-secrets-$STAGE
        #        key: SUPERSECRETTHING
      imagePullSecrets:
        - name: gitlab-registry
```
Most important to notice is our use of environment variables in the manifest file, stuff like ```$CI_ENVIRONMENT_SLUG``` and ```$PORT```.  What happens during the deploy process is that [k8s-deploy-helper](https://github.com/lifechurch/k8s-deploy-helper) will take all the files in the kubernetes directory and run them through the envsubst program which will replace all the environment variables with their values. So, for example, because you said a GitLab variable named ```$PORT``` to 5555 earlier, every instance of $PORT in this file will be replaced with the value ```5555``` before the manifest is sent to Kubernetes. In the manifest, we use variables like $CI_ENVIRONMENT_SLUG as the name of the deployment so that when the different build stages run, they get a unique name before being sent to Kubernetes. This lets you build one deployment file, but use it to maintain separate deployments for review apps, staging and production in Kubernetes. These templates also include the metadata GitLab is looking for in order to find your containers for deploy boards and for connecting to a bash shell in the container through GitLab.

You'll see the same type of logic in service.yaml which sets up a service for each stage (review, staging, production) and ingress.yaml, which sets up a unique ingress host for each stage.  will do this for every manifest file in the root of the kubernetes folder.

Within the kubernetes directory you'll notice a directory called production with an autoscale.yaml file in it. [k8s-deploy-helper](https://github.com/lifechurch/k8s-deploy-helper) will look for directory names within the kubernetes directory that corresponds to the GitLab stage you are currently building it. It will then apply the manifest files in that directory using the same envsubst logic first. This allows you to have stage-specific manifests. In this example, we only want horizontal pod autoscaling for production, not in staging or review.

Please note you are not obligated in any way to use this templated style of manifest building for everything. If you desire, you can have hardcoded manifests and stick them into the appropriately named directories (production, staging, review). We recommend doing this if you have manifests that need to be varied by more than just a simple environment variable. For example, we have an app that has a variety of hostnames we need to pass in for the ingress in production, but not in staging or review. So, for this example we would delete the ingress.yaml in the base directory, and create 3 different ingress.yaml files in the production, staging and review directories.

Pro Tip: Never, ever, ever hardcode replicas if you want to auto scale. 

You'll notice that we have included a commented out section in the deployment.yaml:

```
        #env:
        #  - name: SUPERSECRETTHING
        #    valueFrom:
        #      secretKeyRef:
        #        name: $KUBE_NAMESPACE-secrets-$STAGE
        #        key: SUPERSECRETTHING
```

This is to give you an example of how to use the [k8s-deploy-helper](https://github.com/lifechurch/k8s-deploy-helper) secret management system. Please read the [secret management](https://github.com/lifechurch/k8s-deploy-helper#secret-management) for an overview. Essentially, if you set a GitLab variable in the UI named SECRET_SUPERSECRETTHING, [k8s-deploy-helper](https://github.com/lifechurch/k8s-deploy-helper) will find it, strip off the SECRET_ prefix, and create a Kubernetes secret for it, doing the base64 stuff for you. You could then comment out these lines of code in order to set the SUPERSECRETTHING environment variable to be the Kubernetes secret that [k8s-deploy-helper](https://github.com/lifechurch/k8s-deploy-helper) built for you. Definitely take notes in the docs that you can set stage-specific variables by prefixing the GitLab variable name with either REVIEW_, STAGING_, or PRODUCTION_. [k8s-deploy-helper](https://github.com/lifechurch/k8s-deploy-helper) creates separate secrets for each of your build stages.

This gives you a way for you to manage your secrets within GitLab using a system that has authentication and authorization built-in already to keep your secrets more secure than simply sticking them as plain text in your repo.

[k8s-deploy-helper](https://github.com/lifechurch/k8s-deploy-helper) also creates a secret called gitlab-registry for every project you hook into Kubernetes. We do this because we need a permanent username and password to use that has permissions to login to the Docker registry at GitLab. We can't use the default tokens that GitLab recommends because they are time-limited, so if you need to scale your app onto new nodes it hasn't run on yet, the token would no longer be valid. Please see the [documentation](https://github.com/lifechurch/k8s-deploy-helper#gitlab-credentials) for more information on setting this up.

### Back to .gitlab-ci.yml
Now that we've gone over how [k8s-deploy-helper](https://github.com/lifechurch/k8s-deploy-helper) deploys manifest files for you, lets get back to the GitLab CI configuration.

```
review:
  stage: review
  dependencies: []
  script:
    - command deploy
  environment:
    name: review/$CI_COMMIT_REF_NAME
    url: http://$CI_ENVIRONMENT_SLUG.$KUBE_DOMAIN
    on_stop: stop_review
  only:
    - branches
  except:
    - master

stop_review:
  stage: review
  dependencies: []
  variables:
    GIT_STRATEGY: none
  script:
    - command destroy
  environment:
    name: review/$CI_COMMIT_REF_NAME
    action: stop
  when: manual
  only:
    - branches
  except:
    - master
```
These sections control review apps. The URL you set in ```environment:url``` for all the different build stages. By using ```$CI_ENVIRONMENT_SLUG``` we make sure that each review app has a unique URL.

```
staging:
  stage: staging
  dependencies: []
  script:
    - command deploy
  environment:
    name: staging
    url: http://staging.$KUBE_DOMAIN
  only:
    - master
```
This deploys the master branch to staging. Nothing of particular note here other than ```environment:url```

```
production:
  stage: production
  dependencies: []
  script:
    - command deploy
  environment:
    name: production
    url: http://$KUBE_DOMAIN
  when: manual
  allow_failure: false
  only:
    - master

taglatest:
  stage: taglatest
  dependencies: []
  allow_failure: false
  script:
    - command push
  only:
    - master
```
Production works exactly like all the other stages as far as [k8s-deploy-helper](https://github.com/lifechurch/k8s-deploy-helper) is concerned. In this example however, we made deploying to production a manual job. Once production finishes, we tag the docker image that just got rolled out to production as latest.

That's pretty much it. Take a look at the k8s-deploy-helper source code if you have any questions, it should be fairly self explanatory. 

## More features
Be sure to read the [k8s-deploy-helper docs](https://github.com/lifechurch/k8s-deploy-helper) for other features that weren't highlighted here, such as letting New Relic know when a deploy takes place.













