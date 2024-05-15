Name:           jharmison-l4t-repo
Version:        9
Release:        1
Summary:        repo-l4t.apps.okd.jharmison.com repository configuration

License:        BSD
URL:            https://repo-l4t.apps.okd.jharmison.com
Source1:        jharmison-l4t.repo
Source2:        RPM-GPG-KEY-jharmison-repo.pub
BuildArch:      noarch

Requires:       redhat-release >= %{version}
Provides:       jharmison-l4t-repo(%{version})

%description
repo-l4t.apps.okd.jharmison.com package repository files for dnf along with gpg public keys

%prep
true

%build
true

%install

# Create dirs
install -d -m755 \
  %{buildroot}%{_sysconfdir}/pki/rpm-gpg  \
  %{buildroot}%{_sysconfdir}/yum.repos.d

# GPG Key
%{__install} -Dp -m644 \
    %{SOURCE2} \
    %{buildroot}%{_sysconfdir}/pki/rpm-gpg

# Avoid using basearch in name for the key. Introduced in F18
ln -s $(basename %{SOURCE2}) %{buildroot}%{_sysconfdir}/pki/rpm-gpg/RPM-GPG-KEY-jharmison-l4t

# Yum .repo files
%{__install} -p -m644 \
    %{SOURCE1} \
    %{buildroot}%{_sysconfdir}/yum.repos.d

%files
%config %{_sysconfdir}/pki/rpm-gpg/*
%config(noreplace) %{_sysconfdir}/yum.repos.d/jharmison-l4t.repo

%changelog
* Tue May 14 2024 James Harmison <jharmison@gmail.com> - 9-1
- Initial L4T Repo RPM
