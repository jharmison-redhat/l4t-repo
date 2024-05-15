FROM fedora:40 as builder

ARG GPG_PRIVATE_KEY=""
ARG TLS_VERIFY="true"

ENV GPG_PRIVATE_KEY=${GPG_PRIVATE_KEY} \
    GPG_TTY=/dev/console \
    TLS_VERIFY=${TLS_VERIFY}

# Install repobuild dependencies
RUN dnf -y install createrepo gpg curl jq tree rpmdevtools rpm-build rpm-sign

COPY . /repobuild
WORKDIR /repobuild

# Build the repo, with signatures
RUN ./repobuild.sh

# Fresh container for hosting repo
FROM fedora:40

LABEL org.opencontainers.image.title='Jetpack 6 RPM Repository'
LABEL org.opencontainers.image.description='Repositories as code - Tegra Edition.'
LABEL org.opencontainers.image.authors='James Harmison <jharmison@redhat.com>'
LABEL org.opencontainers.image.licenses="It's Complicated"

RUN dnf -y install nginx \
 && dnf clean all

# Copy only sanitized repo dir
COPY --from=builder /repobuild/repo /repo
COPY nginx.conf /etc/nginx/nginx.conf

USER 1001
EXPOSE 8080
WORKDIR /repo

ENTRYPOINT /usr/sbin/nginx
