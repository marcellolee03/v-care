#!/bin/bash
# Disable weak CBC ciphers for the SSH service.  Handles both Erlang/OTP SSH
# (ssh.app / start_ssh.escript) and an OpenSSH sshd configuration if present.

set -u

SECURE_OPENSSH_CIPHERS='aes256-ctr,aes192-ctr,aes128-ctr'

clear_immutable() {
    [ -e "$1" ] || return 0
    chattr -i "$1" 2>/dev/null || true
}

patch_sshd_config() {
    local cfg="$1"
    [ -f "$cfg" ] || return 0
    clear_immutable "$cfg"
    cp -a "$cfg" "${cfg}.weak-ssh-ciphers.bak" 2>/dev/null || true
    sed -i '/^[[:space:]]*Ciphers[[:space:]]/d' "$cfg" 2>/dev/null || true

    local tmp
    tmp="$(mktemp /tmp/sshd_config.XXXXXX 2>/dev/null)" || return 0
    {
        printf 'Ciphers %s\n' "$SECURE_OPENSSH_CIPHERS"
        cat "$cfg"
    } >"$tmp" 2>/dev/null || { rm -f "$tmp"; return 0; }
    cat "$tmp" >"$cfg" 2>/dev/null || true
    rm -f "$tmp"
    return 0
}

patch_ssh_otp_app() {
    local app="$1"
    [ -f "$app" ] || return 0
    clear_immutable "$app"
    cp -a "$app" "${app}.weak-ssh-ciphers.bak" 2>/dev/null || true

    perl - "$app" <<'PERL'
use strict;
use warnings;

my $file = shift @ARGV;
open(my $in, '<', $file) or exit 0;
local $/;
my $s = <$in>;
close $in;

if ($s =~ /\{env\s*,\s*/s) {
    my $pos = $+[0];
    while ($pos < length($s) && substr($s, $pos, 1) =~ /\s/) {
        $pos++;
    }
    if (substr($s, $pos, 1) eq '[') {
        my ($start, $end) = find_matching($s, $pos);
        if (defined $end) {
            my $list = substr($s, $start, $end - $start + 1);
            my @items = split_top($list);
            my @keep = grep {
                !/^\s*\{\s*modify_algorithms\s*,/s
            } @items;

            my $secure = "{modify_algorithms,[{rm,[{cipher,['3des-cbc','aes128-cbc','aes192-cbc','aes256-cbc']}]}]}";
            my $new = '[' . $secure . (@keep ? ',' . join(',', @keep) : '') . ']';

            if ($new ne $list) {
                substr($s, $start, $end - $start + 1) = $new;
                open(my $out, '>', $file) or exit 0;
                print $out $s;
                close $out;
            }
        }
    }
}
exit 0;

sub find_matching {
    my ($str, $idx) = @_;
    my %pair = ('[' => ']', '{' => '}', '(' => ')');
    my $open = substr($str, $idx, 1);
    my $close = $pair{$open};
    return unless defined $close;

    my $depth = 0;
    my $i = $idx;
    my $quote = '';
    my $len = length($str);
    while ($i < $len) {
        my $c = substr($str, $i, 1);
        if ($quote ne '') {
            if ($c eq '\\') { $i += 2; next; }
            if ($c eq $quote) { $quote = ''; }
            $i++;
            next;
        }
        if ($c eq '"' || $c eq "'") { $quote = $c; $i++; next; }
        if ($c eq '%') {
            my $nl = index($str, "\n", $i);
            $i = ($nl < 0) ? $len : $nl + 1;
            next;
        }
        if ($c eq $open) {
            $depth++;
        } elsif ($c eq $close) {
            $depth--;
            return ($idx, $i) if $depth == 0;
        }
        $i++;
    }
    return;
}

sub split_top {
    my ($list) = @_;
    return () if length($list) < 2;

    my $inner = substr($list, 1, length($list) - 2);
    my @out;
    my $start = 0;
    my $depth = 0;
    my $i = 0;
    my $quote = '';
    my $len = length($inner);

    while ($i < $len) {
        my $c = substr($inner, $i, 1);
        if ($quote ne '') {
            if ($c eq '\\') { $i += 2; next; }
            if ($c eq $quote) { $quote = ''; }
            $i++;
            next;
        }
        if ($c eq '"' || $c eq "'") { $quote = $c; $i++; next; }
        if ($c eq '%') {
            my $nl = index($inner, "\n", $i);
            $i = ($nl < 0) ? $len : $nl + 1;
            next;
        }
        if ($c eq '[' || $c eq '{' || $c eq '(') {
            $depth++;
        } elsif ($c eq ']' || $c eq '}' || $c eq ')') {
            $depth--;
        } elsif ($c eq ',' && $depth == 0) {
            push @out, substr($inner, $start, $i - $start);
            $start = $i + 1;
        }
        $i++;
    }
    push @out, substr($inner, $start) if $start <= $len;

    my @trimmed;
    for my $x (@out) {
        # drop comments, else a trailing one swallows the list's closing bracket
        $x =~ s/\s*%[^\n]*//g;
        $x =~ s/^\s+//;
        $x =~ s/\s+$//;
        push @trimmed, $x if length($x);
    }
    return @trimmed;
}
PERL
}

patch_escript() {
    local f="$1"
    [ -f "$f" ] || return 0
    grep -Iq . "$f" 2>/dev/null || return 0
    clear_immutable "$f"
    cp -a "$f" "${f}.weak-ssh-ciphers.bak" 2>/dev/null || true

    perl - "$f" <<'PERL'
use strict;
use warnings;

my $file = shift @ARGV;
open(my $in, '<', $file) or exit 0;
local $/;
my $s = <$in>;
close $in;

my $orig = $s;
my $changed = 0;

# Wrap direct ssh:daemon/1,2,3 calls so explicit daemon options cannot
# reintroduce the CBC ciphers.
if ($s =~ /\bssh:daemon\s*\(/ &&
    $s =~ /^[ \t]*main\s*\(/m &&
    $s !~ /\bssh_daemon_secure\s*\(/ &&
    $s !~ /\badd_secure_ssh_ciphers\s*\(/) {

    my $helper =
"ssh_daemon_secure(Port) when is_integer(Port) ->\n" .
"    ssh:daemon(Port, add_secure_ssh_ciphers([]));\n" .
"ssh_daemon_secure(Port) ->\n" .
"    ssh:daemon(Port).\n" .
"ssh_daemon_secure(Port, Opts) when is_integer(Port), is_list(Opts) ->\n" .
"    ssh:daemon(Port, add_secure_ssh_ciphers(Opts));\n" .
"ssh_daemon_secure(Port, Opts) ->\n" .
"    ssh:daemon(Port, Opts).\n" .
"ssh_daemon_secure(Port, Address, Opts) when is_integer(Port), is_list(Opts) ->\n" .
"    ssh:daemon(Port, Address, add_secure_ssh_ciphers(Opts));\n" .
"ssh_daemon_secure(Port, Address, Opts) ->\n" .
"    ssh:daemon(Port, Address, Opts).\n" .
"add_secure_ssh_ciphers(Opts) ->\n" .
"    Opts1 = proplists:delete(modify_algorithms, Opts),\n" .
"    [{modify_algorithms, [{rm, [{cipher, ['3des-cbc', 'aes128-cbc', 'aes192-cbc', 'aes256-cbc']}]}]}\n" .
"     | Opts1].\n";

    my $count = ($s =~ s/\bssh:daemon\s*\(/ssh_daemon_secure(/g);
    if ($count) {
        $s =~ s!^([ \t]*main\s*\()!$helper\n$1!m;
        $changed = 1;
    }
}

# Also set the OTP ssh application environment before ssh starts.
if ($s =~ /\bssh\s*:/ &&
    $s !~ /application:set_env\s*\(\s*ssh\s*,\s*modify_algorithms\s*,\s*\[\s*\{rm,\s*\[\s*\{cipher,\s*\['3des-cbc'/s) {

    my $env_inject =
"application:load(ssh),\n" .
"    application:set_env(ssh, modify_algorithms, [{rm, [{cipher, ['3des-cbc', 'aes128-cbc', 'aes192-cbc', 'aes256-cbc']}]}]),";

    my $n = 0;
    $n += ($s =~ s!^([ \t]*main\s*\([^)]*\)\s*->)!$1\n    $env_inject!gms);
    $n += ($s =~ s!^([ \t]*main\s*\([^)]*\)\s*when\s+[^\n]*?->)!$1\n    $env_inject!gms);
    $changed = 1 if $n;
}

if ($changed && $s ne $orig) {
    open(my $out, '>', $file) or exit 0;
    print $out $s;
    close $out;
}
exit 0;
PERL
}

# OpenSSH-style server configurations.
while IFS= read -r cfg; do
    patch_sshd_config "$cfg"
done < <(find /etc /usr /opt /var /root /home /srv -xdev -name 'sshd_config' 2>/dev/null)

# Erlang/OTP SSH application defaults.
while IFS= read -r app; do
    patch_ssh_otp_app "$app"
done < <(find /usr /opt /var /root /home /srv -xdev -name 'ssh.app' 2>/dev/null)

# Erlang SSH launcher scripts.
while IFS= read -r script; do
    patch_escript "$script"
done < <(find /etc /usr /opt /var /root /home /srv -xdev \( -name 'start_ssh.escript' -o -name '*ssh*.escript' \) 2>/dev/null)

exit 0