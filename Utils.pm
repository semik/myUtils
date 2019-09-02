#!/usr/bin/perl -w

# dep: apt-get install libproc-processtable-perl libnet-dns-perl

package myUtils::Utils;

use strict;
use vars qw($VERSION @ISA %EXPORT_TAGS);

use Sys::Syslog qw(:standard :macros);
use Proc::ProcessTable;
use Net::DNS;

my $prg_name = $0;
$prg_name =~ s/.*\///;
my $PID_dir="/tmp";

@ISA = qw(Exporter);
$VERSION = "0.0.1";
%EXPORT_TAGS = (
		all => [qw(PID_dir prg_name resolveHostname logger local_die startRun stopRun)]
	       );

# Add Everything in %EXPORT_TAGS to @EXPORT_OK
Exporter::export_ok_tags('all');

sub resolveHostname {
  my $hostname = shift;
  my $start = time;
  my $retry = 5;
  my $query;

  my $dns_resolver = Net::DNS::Resolver->new;
  $dns_resolver->persistent_udp(1);
  $dns_resolver->udp_timeout(3);

  do {
    $query = $dns_resolver->search($hostname);
    $retry--;
  } until (defined($query) or ($retry <= 0));

  if ($query) {
    foreach my $rr ($query->answer) {
      next unless $rr->type eq "A";
      my $stop_diff = time-$start;
      if ($stop_diff >= 3) {
	# tenhle cyklus tady byl hlavne kvuli tomu kdyz jsem to
	# poustel rucne abych vedel proc to tak trva, pravedepobne by
	# melo smysl to vyhodit
	logger(LOG_WARNING, "Too slow resolving for $hostname ${stop_diff}.");
      };
      return $rr->address;
    }
  } else {
    logger(LOG_ERR, "DNS query for $hostname failed with error: ".$dns_resolver->errorstring);
    return undef;
  };

  logger(LOG_ERR, "DNS query for $hostname failed in terrible way. This should not happen");
};

sub syslog_escape {
  my $str = shift;
  my @chr = split(//, $str);

  for(my $i=0; $i<@chr; $i++) {
    if (ord($chr[$i])>127) {
      $chr[$i] = sprintf('\0x%X', ord($chr[$i]));
    };
  };

  return join('', @chr);
};

sub logger {
  my $priority = shift;
  my $msg = shift;

  openlog($prg_name, 'pid', LOG_LOCAL1);
  setlogmask(LOG_MASK(LOG_ALERT) | LOG_MASK(LOG_CRIT) |
             LOG_MASK(LOG_DEBUG) | LOG_MASK(LOG_EMERG) |
             LOG_MASK(LOG_ERR) | LOG_MASK(LOG_INFO) |
             LOG_MASK(LOG_NOTICE) | LOG_MASK(LOG_WARNING));
  syslog($priority, syslog_escape($msg));
  closelog;
};

sub local_die {
  my $message = shift;

  logger(LOG_ERR, $message);
  exit(1);
};

sub startRun {
  my $prg = shift || $0;
  $prg =~ s/.*\///;
  my $pidFile = "$PID_dir/$prg.pid";

  my $counter = 1;
  while ((-e $pidFile) and ($counter > 0)) {
    logger(LOG_INFO, "File \"$pidFile\" in way, waiting ($counter).");
    sleep 5;
    $counter--;
  };

  if (-e $pidFile) {
    open(PID, "<$pidFile") or die "Can't read file \"$pidFile\"";
    my $pid = <PID>; chomp($pid);
    close(PID);

    my $t = new Proc::ProcessTable;
    my $found = 0;
    foreach my $p ( @{$t->table} ){
      $found = 1 if ($p->pid == $pid);
    };

    if ($found) {
      my $msg = "We are already running as PID=$pid, terminating!";
      logger(LOG_ERR, $msg);
      exit 1;
      die $msg;
    }

    logger(LOG_INFO, "Overwriting orphaned PID file \"$pidFile\"");
  };

  open(RUN, ">$pidFile") or die "Can't create file \"$pidFile\": $!";
  print RUN $$;
  close(RUN);
};

sub stopRun {
  my $prg = shift || $0;
  $prg =~ s/.*\///;
  my $pidFile = "$PID_dir/$prg.pid";

  die "Can't remove file \"$pidFile\"! " unless unlink("$pidFile");
};

1;
