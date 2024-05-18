l4t-repo
========

This code base is designed to take a collection of RPMs and publish them as an RPM repo to enable installation with `dnf`.

I use it to build a bootc image with the RPMs included, without needing to pack them directly into the image and making them simple to update, for example when a new kmod is published for a new kernel.

Usage
-----

You need an OpenShift or OKD cluster with the internal image registry exposed through a Route or Ingress, as we use an ImageStream to trigger a Deployment rollout on `push`. Create a Namespace, here we're assuming `l4t` so you might run `oc create ns l4t`, and ensure you're logged in to be able to push images to the registry from your local container runtime via `oc registry login` or similar.

Ensure that you've copied the RPMs you want packaged into `repo/$releasever/$basearch`. In particular, for this project, our goal is to serve the Jetpack 6 / Linux for Tegra (l4t) RPMs, so you should put them in `repo/9/aarch64/`.

Update `deploy/kustomization.yaml` to patch the Route to refer to your new URL, and adjust `dist/SPECS/jharmison-l4t-repo.spec` and `dist/SOURCES/jharmison-l4t.repo` to point to that new Route.

In order to sign the RPM repo, you need a GPG private key (whose public key will be served along with the repo). You should store this in unarmored format adjacent to the `Makefile` in `repo.asc`.

Run `make`, overriding the registry for the push via `make REGISTRY=${YOUR_REGISTRY_HOSTNAME}` - the image is built, the repo is signed, and the deployment is applied. You will now be able to enable the repo by installing `${ROUTE}/jharmison-l4t-repo-9.rpm` and then install packages from it. In particular, we're interested in `nvidia-jetpack-kmod` and `nvidia-jetpack-all`, but those RPMs are not part of the code base for hosting the repo.
