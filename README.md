
_2019-09-20 The Y-stack readme is just a quick-start. For break-down of paragraphs and terms see my lecture [Slides](https://docs.google.com/presentation/d/1tnMORT5a3ucAxf9I_ZClLYvbCJsRmfK_HT1Q6HPETow/edit?usp=sharing) to engineering masters' students at [Chalmers](http://www.cse.chalmers.se/edu/course/DAT300/)._

# To deliver software using Kubernetes

Ignoring everything that’s cool and fun, Kubernetes just means a bunch of machines - physical or virtual - running a bunch of processes. Machines are called _nodes_ and if they’re Linux you can open a remote shell on them an run `ps -aux` to list these processes.

Processes can be called programs but the Kubernetes _community_ -- more about the community later -- prefers the term _workload_ because tasks you carry out may be spread across nodes as multiple processes. That’s a _distributed system_ and Kubernetes is one way to _orchestrate_ processes: manage how they are started and stopped across nodes.

Distributed systems is not only fun. Its principles let you _scale_ your service without the exponential cost increase of paying for ever more powerful machines. You'll also, rougly speaking, be able to increase robustness -- _availability_ -- without the exponential cost increase of rasing the quality of your code.

Y-stack -- _ystack_ when in code -- lets you explore such advantages: for example use monitoring and alerts instead of error handling, or retries instead of code that validates preconditions. Y-stack is _opinionated_ in ways that make it self-sufficient as a _source-to-URL_ Platform-As-A-Service. In other words you can write your code and run the result it in your browser usnig only your development environment and your Y-stack.

Regarding “your code”: to describe why Kubernetes is a paradigm shift compared to batch-executing commands across machines we need to raise the requirements a bit.

 1. Your code runs as multiple executables. Were it a single executable you could simply bundle all _dependencies_ with it and distribute the package to every node.
 2. Your processes only provide value if accessible from clients, be it browsers or data pipelines.
 3. Your software get upgraded, fails and behaves in unanticipated ways just like any other piece of non-trivial software.
 4. Clusters (and machines) are _disposable_. Sooner or later you’ll want to _migrate_ your _stateless_ and _stateful_ workload to a next generation Kubernetes setup.

A deep dive into these aspects will take us to the design decisions behind Y-stack, the result of a journey that the startup Yolean made from a virtual machine per customer to a distributed system that made development, and more importantly _maintenance_, fun and quite efficient. 

## 1. Your code’s dependencies

You typically have _build time_ and _run time_ dependencies. With Java you might pull libraries from a public Maven repository and depend on a particular major version of the JVM. With Python you have PyPA but mmay also depend at runtime on pre-installed libraries. With Node.js you expect every runtime environment to run `npm install` for you.

Dealing with dependencies used to suck. Nevermind the _toil_ - boring repetitive labor - which also sucked, any upgrade of one service risked the stability of other services, and you probably wouldn’t notice until that other service had a restart months later.

Long story short, the technology company Docker made _containers_ available to us develpers-without-a-high-tech-infra-team. _Containerization_ meant that regardless of which language we used the _build time_ output could run wherever a single _run time_ dependency was present: the _container runtime_.

Actually we need to chose one container runtime from a handful of viable options, but that’s no big deal because these days they agree on the _image_ format. We’ll get to the concept of _primitives_ further down, but let’s warm up with a closer look at two of the fundamental ones:

### Container _image_s

https://docs.google.com/presentation/d/1tnMORT5a3ucAxf9I_ZClLYvbCJsRmfK_HT1Q6HPETow/edit#slide=id.g60279120f7_0_68

### Image _registry_

https://docs.google.com/presentation/d/1tnMORT5a3ucAxf9I_ZClLYvbCJsRmfK_HT1Q6HPETow/edit#slide=id.g60279120f7_0_73

## 2. Client access 

Let’s use the term “customer” to denote those who find your service(s) valuable, and thus want access to the running software. Now that it’s distributed there’s no longer a single address to hand over to your customer, and even if there was one it’d probably change as nodes come and go.

Kubernetes supports a basic mechanism that makes use of _service discovery_: You can expose a “node port” on every machine and let it point to all currently running _instances_ of your service. You can use DNS to point a domain to all your machines. Your customer gets the DNS domain name and the port number and is good to go.

In practice, for reasons currently out of scope with this document, you’ll want a layer of indirection. Look for the terms _ingress_ or _load balancer_.

## 3. Upgrades

Yolean’s engineers had the pleasure of visiting a talk by Eng from a Spotify backend team. He made a convincing case that “you’re always in a migration” which stuck a chord: After maintaining an ever-pivoting service for seven years we’ve learned that our up-front platform decisions (often made under time pressure that leaves room only for what’s value adding) always need to be revised. Such revision is painful, but not as paralyzing as trying to make the right decision from the outset.

The point is that upgrades involve more than just new releases of your code: Dependencies may change, persisted data may need migration, the old version(s) should stay around. A second and equally important point is that such _maintenance_ involves more than one person. Single-maintaner development is great for quickly producing an MVP, but for anything that has gained customers it’s a major business risk.

Maintenance is expressed as _primitives_. When combined with a source version control system like Git and containerization terminology from Docker, Kubernetes provides all the primitives you need and therefore a language: For an example upgrade you may want to change the Labels of a Deployment called “maintenance-message-display” so that it matches your customer-facing Service’s Selector while you’ve Scaled down your frontend Deployment to zero Replicas, after which you trigger a Snapshot of your database StatefulSet Persistent Volumes, then Create a Job that migrates a the database schema, then Apply a new image Tag built from source commit 0b8d45fd16 to trigger a Rolling Upgrade of your Pods that to the SQL. Right?

## 4. Disposable infrastructure

Once upon a time servers had names. That culture survived the shift to virtual machines. With Kubernetes, the sooner you get emotinally detached from your machines the better. Let’s continue our example journey in primitives:

When you’re in the middle of an upgrade, suddenly a Node gets low on memory Resources (probably because you lack some Limits) and Eviction is initiated on a workload you assigned low Priority. Termination however is too slow and the Node stops reporting the essential Status per Pod that you depend on (through the Kubernets API) for your upgrade. You hit the public URL and with some relief see the Customers’ maintenance message. Watching events through the `kubectl` client you notice OOMKilled on Pods you thought were unaffected by this upgrade. Better safe than sorry, you use your _hosting provider_’s tooling to add a Node to your cluster, and as soon as possble Cordon the unreliable node...

(A great resource for learning more about Kubernetes, both lingo and practice, is https://k8s.af/.)

There’s a few observations to make here:

Observation A: Kubernetes is an abstraction that hides a fair bit of complexity. When things fail you’ll wish you understood what’s happening under the user interface. That’s where it pays off to have developed your software with something like Y-stack where along the way you did _dare to experiment_ in a _production-like environment_ with producton-like _monitoring_.

Observation B: Kubernetes automates things. In the half-panicked spectator situation you’ll wish  you had a pause button (spoiler alert: you don’t). You’ll also start thinking along the lines of _failover_. Given that persistent data remains consistent, will you be able to restore the service? Customers don’t care about servers, so maybe you can simply set up a new cluster and reconfigure your _load balancer_ (mentioned above but still not explained)?

Kubernetes makes it possible, though still far from trivial, to define your setup _declaratively_. The value of that is clear from lessons learned with virtual machines: People running _operations_ executed assorted commands on servers, i.e. _imperative_ maintenance. It turned out to be unmainainable over time, and thus tools like Chef, Ansible, Puppet and Cloud Formation popped up. Kubernetes prioritized declarative management from its inception. In principle, and in reality if you test for it, your entire stack can be “spun up” on a new cluster from a different hosting provider with zero modification to your Resource Definitions.

That concludes our four core requirements and leads to a buzzword we’ve avoided until now: DevOps.

## DevOps

The meaning of DevOps is hard to grasp online because it’s used to sell you anything that can promise increased productivity related to software development. In our context DevOps means that developers need to deal with the part of maintenance that is _operations_, which means to deliver their work to customers and interact with it under real load. It’s not about cost-cutting (SRE people can support us in new and more valuable ways) but about LEAN product development: small increments, validated learnings, etc.

Once again Y-stack takes the view that if you can experiment with all layers of software delivery you’re better prepared to maintain and improve your product.

There are aspects of maintenance that should be kept outside DevOps, and the Kubernetes user interface matches that boundary quite well. We recommend that, when time comes to take your product online, you don’t rent machines but instead pay for Kubernetes-as-a-service. Machines is one of the building blocks that your hosting provider selects, together with for example networking. You avoid things like `kubeadm`, `kubelet`s, “api server flags”, certificates and expect `kubectl get nodes` to produce a list of Ready instances a few minutes after you’ve paid the first bill.

In Yolean’s experience DevOps could never work at the machine level. We do want the developer role to be broad and challenging+interesting, but when we include the health of machines in that the specta is to wide to be enjoyable. We can either avoid building a distributed system (can we?) or we have to somehow hide many of the complexities.

## The deal with complexity

Y-stack adds complexity to your already complex while empty Kubernetes cluster: for example tooling to build images from source and to let nodes pull these images in order to start containers. In addition there are a few utilities to try to automate _provisioning_ (creating a compatible cluster locally, or at a cloud provider). We’ve automated using bash scripts because we actually want the abstraction (on top of virtualization or cloud provider tooling) to be _leaky_.

We argue that this complexity is _a_ solution to your need to settle at a level of DevOps. It merely resolves the Catch 22 where in order to learn Kubernetes you need to know enough Kubernetes to run your code there. Without the extra layer you can’t really get started without someone to provide you with the source-to-URL pipeline. Make no mistake: many are keen to provide that pipeline (look for CloudRun, PaaS etc) but we advise you to consider these aspects: Stay vendor-neutral as it’s a main selling point for Kubernetes, rely on tooling that proliferates organically in the Kubernetes community that is an ever stronger selling point, and recognize that you’re looking not for an all-in-one but for a starting point.

Both _provision_ and the subsequent _converge_ adds truckloads of complexity compared to a local development stack, but believe it or not it’s a minimal starting point for developers to actually l e a r n Kubernetes.

## The community

It’s 2019 now and there’s no longer a need to defend trust on Open Source for business-critical software. You should however pay attention to the different kinds of open source. The Kubernetes community is unhealthily self-aware as an Awesome Community, but that’s ok when any impartial review would also call it great, as in valuable to us who depend on the tool.

Most notably the Kubernetes community can be relied on because there’s no single controlling actor that has a business model built on it, while still being commercially important enough to receive robust maintenance. For example it spends [upward of $3 million per year](https://www.cncf.io/announcement/2018/08/29/cncf-receives-9-million-cloud-credit-grant-from-google/) on "running the continuous integration and continuous delivery (CI/CD) pipelines and providing the container image download repository.".

## Security

Containerization and trust

Isolation

Multi-tenancy

## Cost

Resource utilization

## More thorough presentations

Purely technical:
 - https://github.com/cncf/presentations/tree/master/kubernetes
 - https://github.com/jbeda/slides-kubernetes-101

A light introduction of Kubernete followed by deep dive: https://drive.google.com/file/d/1Lfi8r0GZdFIMgprUrwaf-Lru5RsctML7/view

Quite related to the scope of Y-stack: https://speakerdeck.com/luxas/what-does-production-ready-really-mean-for-a-kubernetes-cluster-umea-may-2019?slide=5

Good development perspective: https://speakerdeck.com/mhausenblas/developing-on-kubernetes?slide=16

The model we've chosen, only we transfer _build contexts_ not images: https://speakerdeck.com/mhausenblas/developing-on-kubernetes?slide=25

# Y-stack

Y-stack is a micro-PaaS(?) with the following goals:

 - Allow every developer to experiment with architecture on a _cluster level_
 - Make moitoring and alerts a first class tool in coding
 - Make Kubernetes patterns like sidecars and operators an intergral part of design
 - Support event-driven microservices patterns

## Why

Y-stack is higly opinionated:
It says "registry" to refer to a Docker registry with a particular setup,
while "knative" refers to an installer that combines Knative modules.
The point with being opinionated is that registry and knative work well together.

The stack supports local developmment ("inner development loop") using
[Skaffold](https://skaffold.dev/)
with local and remote clusters alike.
Image builds during development are in-cluster:
Many dev setups transfer container images but we transfer the build context.
We see builds as temporary and per-cluster,
though they upon different kinds of verification can be pushed to a productiono registry.
Build contexts are small and there's no need to git push to trigger a build.

Y-stack should be independent of cluster vendor,
but we provide some utilities like [microk8s-multipass.sh](./microk8s-multipass.sh) to automate cluster creation.
Note that these scripts don't actually apply anything.
Actually installing y-stack is done through `kubectl apply -k [path(s) in this repo]`.

## TLS certificate for https

A crucial part of modern development is to access your stack using `https://`.
For that you need a valid SSL certificate.
If your cluster has a public IP we assume that you can get real valid certificats,
through for example LetsEncrypt.

If your cluster has a local IP you'll probably want something like [mkcert](https://github.com/FiloSottile/mkcert).
It needs to run locally, so y-stack can't automate much, but some assistance is provided in the form of:
 - A Kustomize base for ingress at [ingress-tls-local](./ingress-tls-local/) which as base for actual ingress resources helps with the transfer of a local cert to in-cluster Ingress.
 - A utility [tls-local.sh](./tls-local.sh) to (re)generate certs for all `host:` entries in any ingress resource.

Unless you have a local DNS that gets updated with your ingress entries,
you'll probably also want to update your /etc/hosts file.
For that we use https://github.com/solsson/k8s-ingress-hosts/releases

## Installation

Add `YSTACK_HOME` env poiting to the root of y-stack, and `$YSTACK_HOME/bin` to path.

## Kubectl context management

At Yolean we share kubectl commands that target a specific cluster and namespace.
This is so that when you copy a command from Slack or a readme, you don't accidentally target a prod cluster.

Cluster management is however _outside_ the scope of Y-stack. Instead look at tools like:
 * https://github.com/jonmosco/kube-ps1
 * https://github.com/aluxian/fish-kube-prompt
 * https://github.com/superbrothers/zsh-kubectl-prompt
 * https://github.com/postfinance/kubectl-ctx
 * https://github.com/jordanwilson230/kubectl-plugins#kubectl-switch
 * https://github.com/solsson/bash-kubectl-git/pull/3

Our policy also implies that we need some bot warning against kubectl without `--context` or `--namespace` in Slack,
and likewise some CI tool that enforces kubectl hygiene in markdown.

One more thing: We need to agree on kubectl context names. How do we share those?

## Dependencies

Y-stack doesn't have a CLI, but depends on assorted tooling from the Kubernetes community.
To ease the burden of maintaining a dev stack, there's tooling to keep these binaries updated.
If a requred binary exists in path, a version check is performed.
If not it is downloaded and placed in `$YSTACK_HOME/bin`.


## Hooks

The y-build command is a general purpose util to build a service from its source folder.
Builds are rarely generic though, so it first invokes an executable file `build-pre` in `$YSTACK_HOOKS` if existent.
`$YSTACK_HOOKS` defaults to `$YSTACK_HOME/hooks`.

`y-build-buldkit-host` selects a buildkitd endpoint.

## Namespace

Why do we name the stack namespace with a stage, for example `ystack-dev`?
Still doesn't guard against mistakes, because `kubectl -n ystack-dev delete pod`

## Cluster setup

1. Provision
   - Look for [bin](./bin)s named `y-cluster-provision-*`
   - ... but note that all of them are hacks that you'll probably need to understand
   - Provision rougly means setting up a new cluster for:
     - Kubectl access with current (or default) `KUBECONFIG`
     - Current user can configure rbac
     - A default namespace selected (not used yet)
     - Creates namespace `ystack`
     - Set up container runtime to support insecure pull from `builds-registry.ystack.svc.cluster.local`
   - After provision the cluster should be ready to run Y-stack coponents. Unlike scripts, paths that support `apply -k` should be declarative resource config that you can re-apply and extend.
2. Converge `kubectl apply -k converge-generic/`
   - The `converge-generic` kustomization sets `namespace: ystack`,
     but individual features only set namespace if thery have configuration that depend on a fixed namespace
3. Forward
   - port-forward the dev stack for local development
   - `sudo -E y-kubefwd svc -n ystack`
4. Test "inner development loop"
   - Check that CLIs are ok using `y-buildctl` and `y-skaffold`
   - In `./examples/basic-dev-inner-loop/` run `skaffold dev`

## Tooling

Y-stack is opinionated on Kubernetes devops tooling as well.
We therefore download some CLIs to the aforementioned `PATH` entry.
