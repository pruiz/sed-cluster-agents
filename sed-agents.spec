%{!?srcver:	%define srcver 1.0}
%{!?srcrev:	%define srcrev master}
%{!?buildno:	%define buildno 3}

%define _provider netway

%if 0%{?fedora} || 0%{?centos_version} || 0%{?rhel}
## OCF resource scripts are arch-independent.
%global _libdir /usr/lib
%endif


Name:           sed-agents
Version:        %{srcver}
Release:        %{buildno}.%{srcrev}%{?dist}
Summary:        Open Cluster Framework (OCF) resource agents for TCG/SED/OPAL disk encryption.
Group:          System Environment/Base
License:        GPL
URL:            http://www.github.com/pruiz/sed-cluster-agents
Source:		%{name}-%{srcrev}.tar.gz
BuildRoot:      %(mktemp -ud %{_tmppath}/%{name}-%{version}-%{release}-XXXXXX)
Requires:       resource-agents
Requires:	sedutil
BuildArch:      noarch

%description
Open Cluster Framework (OCF) resource agents for TCG/SED/OPAL disk encryption.

%prep
mkdir -p "%{name}-%{srcrev}"
tar -zxvf %{SOURCE0} --strip-components=1 -C "%{name}-%{srcrev}"

%build

%install
rm -rf %{buildroot}
cd "%{name}-%{srcrev}"

install -d "%{buildroot}%{_libdir}/ocf/lib/%{_provider}"
install -d "%{buildroot}%{_libdir}/ocf/resource.d/%{_provider}"

install -m 755 sed-unlock.sh "%{buildroot}%{_libdir}/ocf/resource.d/%{_provider}/sed-unlock"

%clean
rm -rf %{buildroot}

%files
%defattr(-,root,root,-)
%attr(755,root,root) %{_libdir}/ocf/resource.d/%{_provider}/sed-unlock

%changelog

