%global crate matugen

Name:           matugen
Version:        4.1.0
Release:        1%{?dist}
Summary:        A material you and base16 color generation tool with templates

License:        GPL-2.0-or-later
URL:            https://github.com/InioX/matugen
Source0:        %{url}/archive/refs/tags/v%{version}.tar.gz#/%{name}-%{version}.tar.gz

ExclusiveArch:  x86_64 aarch64

BuildRequires:  cargo >= 1.75
BuildRequires:  rust >= 1.75
BuildRequires:  gcc

%description
Matugen is a material you and base16 color generation tool. It generates color
schemes from images using Material You algorithms and applies them to templates
for theming your desktop environment.

%prep
%autosetup -n %{name}-%{version}

%build
export RUSTUP_TOOLCHAIN=stable
export CARGO_TARGET_DIR=target
cargo build --release --locked

%install
install -Dpm 0755 target/release/matugen %{buildroot}%{_bindir}/matugen

%files
%license LICENSE
%{_bindir}/matugen
