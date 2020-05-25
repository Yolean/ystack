# Port 443 access to registry

WARNING: The registry setup isn't meant to be public, so don't apply this base to public cloud clusters.

You might still want this setup for local development, for example `skaffold dev` with local docker and image urls `builds.registry.svc.cluster.local/...`.
A more private alternative is `kubectl port-forward` but you need some tricks there to preserve default 80 and 443.

Also it can be an alternative to [regstry tls](../generc-tls).

For https ingress see [../ingress-tls](../ingress-tls).
