#!/usr/bin/perl
use strict;
use warnings;
use 5.30.0;
no autovivification;
binmode STDOUT, ":utf8";
use utf8;
use Data::Printer;
use Data::Dumper;
use JSON;
use Scalar::Util qw(looks_like_number);
use FindBin;
use lib "$FindBin::Bin/../../lib";

# Project's libraries.
use global;
use time;

my %ecdcReactionsOld = ();
say "Loading old reactions ...";
my $oldR = $dbh->selectall_hashref("SELECT id as ecdcReactionId, name as reactionName FROM openvaet_test_2.ecdc_reaction", 'ecdcReactionId');
for my $ecdcReactionId (sort{$a <=> $b} keys %$oldR) {
	my $reactionName = %$oldR{$ecdcReactionId}->{'reactionName'} // die;
	$ecdcReactionsOld{$ecdcReactionId}->{'reactionName'} = $reactionName;
}

my %ecdcReactionsNew = ();
say "Loading new reactions ...";
my $newR = $dbh->selectall_hashref("SELECT id as ecdcReactionId, name as reactionName FROM openvaet.ecdc_reaction", 'ecdcReactionId');
for my $ecdcReactionId (sort{$a <=> $b} keys %$newR) {
	my $reactionName = %$newR{$ecdcReactionId}->{'reactionName'} // die;
	$ecdcReactionsNew{$ecdcReactionId}->{'reactionName'} = $reactionName;
}

my %ecdcNoticesOld = ();
say "Loading old notices ...";
my $old = $dbh->selectall_hashref("SELECT id as ecdcNoticeId, ecdcSeriousness, internalId, ecdcReporterType, ecdcGeographicalOrigin, ecdcAgeGroup, ecdcSexId FROM openvaet_test_2.ecdc_notice", 'ecdcNoticeId');
for my $ecdcNoticeId (sort{$a <=> $b} keys %$old) {
	my $internalId = %$old{$ecdcNoticeId}->{'internalId'} // die;
	my $ecdcSeriousness = %$old{$ecdcNoticeId}->{'ecdcSeriousness'} // die;
	my $ecdcReporterType = %$old{$ecdcNoticeId}->{'ecdcReporterType'} // die;
	my $ecdcGeographicalOrigin = %$old{$ecdcNoticeId}->{'ecdcGeographicalOrigin'} // die;
	my $ecdcAgeGroup = %$old{$ecdcNoticeId}->{'ecdcAgeGroup'} // die;
	my $ecdcSexId = %$old{$ecdcNoticeId}->{'ecdcSexId'} // die;
	$ecdcNoticesOld{$internalId}->{'oldId'} = $ecdcNoticeId;
	$ecdcNoticesOld{$internalId}->{'ecdcSeriousness'} = $ecdcSeriousness;
	$ecdcNoticesOld{$internalId}->{'ecdcReporterType'} = $ecdcReporterType;
	$ecdcNoticesOld{$internalId}->{'ecdcGeographicalOrigin'} = $ecdcGeographicalOrigin;
	$ecdcNoticesOld{$internalId}->{'ecdcAgeGroup'} = $ecdcAgeGroup;
	$ecdcNoticesOld{$internalId}->{'ecdcSexId'} = $ecdcSexId;
}

my %requalifiedNotices = ();
say "Loading new notices ...";
my $new = $dbh->selectall_hashref("SELECT id as ecdcNoticeId, ecdcSeriousness, internalId, ecdcReporterType, ecdcGeographicalOrigin, ecdcAgeGroup, ecdcSexId FROM openvaet.ecdc_notice", 'ecdcNoticeId');
for my $ecdcNoticeId (sort{$a <=> $b} keys %$new) {
	my $internalId = %$new{$ecdcNoticeId}->{'internalId'} // die;
	my $ecdcSeriousness = %$new{$ecdcNoticeId}->{'ecdcSeriousness'} // die;
	my $ecdcReporterType = %$new{$ecdcNoticeId}->{'ecdcReporterType'} // die;
	my $ecdcGeographicalOrigin = %$new{$ecdcNoticeId}->{'ecdcGeographicalOrigin'} // die;
	my $ecdcAgeGroup = %$new{$ecdcNoticeId}->{'ecdcAgeGroup'} // die;
	my $ecdcSexId = %$new{$ecdcNoticeId}->{'ecdcSexId'} // die;
	if (exists $ecdcNoticesOld{$internalId}->{'ecdcSeriousness'} && ($ecdcNoticesOld{$internalId}->{'ecdcSeriousness'} != $ecdcSeriousness)) {
		$requalifiedNotices{$internalId}->{'from'} = $ecdcNoticesOld{$internalId}->{'ecdcSeriousness'};
		$requalifiedNotices{$internalId}->{'to'} = $ecdcSeriousness;
		$requalifiedNotices{$internalId}->{'newId'} = $ecdcNoticeId;
		if (exists $ecdcNoticesOld{$internalId}->{'ecdcReporterType'} && ($ecdcNoticesOld{$internalId}->{'ecdcReporterType'} != $ecdcReporterType)) {
			die;
		}
		if (exists $ecdcNoticesOld{$internalId}->{'ecdcGeographicalOrigin'} && ($ecdcNoticesOld{$internalId}->{'ecdcGeographicalOrigin'} != $ecdcGeographicalOrigin)) {
			die;
		}
		if (exists $ecdcNoticesOld{$internalId}->{'ecdcAgeGroup'} && ($ecdcNoticesOld{$internalId}->{'ecdcAgeGroup'} != $ecdcAgeGroup)) {
			die;
		}
		if (exists $ecdcNoticesOld{$internalId}->{'ecdcSexId'} && ($ecdcNoticesOld{$internalId}->{'ecdcSexId'} != $ecdcSexId)) {
			die;
		}
		$requalifiedNotices{$internalId}->{'ecdcReporterType'} = $ecdcReporterType;
		$requalifiedNotices{$internalId}->{'ecdcGeographicalOrigin'} = $ecdcGeographicalOrigin;
		$requalifiedNotices{$internalId}->{'ecdcAgeGroup'} = $ecdcAgeGroup;
		$requalifiedNotices{$internalId}->{'ecdcSexId'} = $ecdcSexId;
	}
}

my %requalifications = ();
my $requalified = 0;
for my $internalId (sort keys %requalifiedNotices) {
	my $from = $requalifiedNotices{$internalId}->{'from'} // die;
	$from    = convert_seriousness($from);
	my $to   = $requalifiedNotices{$internalId}->{'to'} // die;
	$to      = convert_seriousness($to);

	# Fetching symptoms for these notices.
	my $oldId    = $ecdcNoticesOld{$internalId}->{'oldId'} // die;
	my $newId    = $requalifiedNotices{$internalId}->{'newId'} // die;
	my $reactionsOld;
	my $symptomsTbOld = $dbh->selectall_hashref("SELECT ecdcReactionId FROM openvaet_test_2.ecdc_notice_reaction WHERE ecdcNoticeId = $oldId", 'ecdcReactionId');
 	for my $ecdcReactionId (sort{$a <=> $b} keys %$symptomsTbOld) {
 		my $reactionName = $ecdcReactionsOld{$ecdcReactionId}->{'reactionName'} // die;
 		$reactionsOld .= ", $reactionName" if $reactionsOld;
 		$reactionsOld = $reactionName if !$reactionsOld;
 	}
	my $reactionsNew;
	my $symptomsTbNew = $dbh->selectall_hashref("SELECT ecdcReactionId FROM openvaet.ecdc_notice_reaction WHERE ecdcNoticeId = $oldId", 'ecdcReactionId');
 	for my $ecdcReactionId (sort{$a <=> $b} keys %$symptomsTbNew) {
 		my $reactionName = $ecdcReactionsNew{$ecdcReactionId}->{'reactionName'} // die;
 		$reactionsNew .= ", $reactionName" if $reactionsNew;
 		$reactionsNew = $reactionName if !$reactionsNew;
		$requalifications{$from}->{$to}->{'byReactions'}->{$reactionName}++;
 	}
 	die "$reactionsNew ne $reactionsOld" if $reactionsNew ne $reactionsOld;
	say "[$internalId] : from [$from] to [$to]";
	say "symptoms :";
	say "[$reactionsOld]";

	my $ecdcReporterType       = $requalifiedNotices{$internalId}->{'ecdcReporterType'}       // die;
	my $ecdcGeographicalOrigin = $requalifiedNotices{$internalId}->{'ecdcGeographicalOrigin'} // die;
	my $ecdcAgeGroup           = $requalifiedNotices{$internalId}->{'ecdcAgeGroup'}           // die;
	my $ecdcSexId              = $requalifiedNotices{$internalId}->{'ecdcSexId'}              // die;
	say "ecdcReporterType       : [$ecdcReporterType]";
	say "ecdcGeographicalOrigin : [$ecdcGeographicalOrigin]";
	say "ecdcAgeGroup           : [$ecdcAgeGroup]";
	say "ecdcSexId              : [$ecdcSexId]";
	$requalifications{$from}->{$to}->{'total'}++;
	$requalifications{$from}->{$to}->{'byReporterType'}->{$ecdcReporterType}++;
	$requalifications{$from}->{$to}->{'byGeographicaOrigin'}->{$ecdcGeographicalOrigin}++;
	$requalifications{$from}->{$to}->{'byAgeGroup'}->{$ecdcAgeGroup}++;
	$requalifications{$from}->{$to}->{'bySexe'}->{$ecdcSexId}++;
	# say "to :"
	# say "[$reactionsNew]";
	$requalified++;
}
say "[$requalified] notices have been requalified.";
p%requalifications;

sub convert_seriousness {
	my ($seriousness) = @_;
	if ($seriousness == 1) {
		$seriousness = 'Serious';
	} elsif ($seriousness == 2) {
		$seriousness = 'Non-Serious'
	} elsif ($seriousness == 3) {
		$seriousness = 'Not Available'
	} else {
		die "seriousness : $seriousness";
	}
	return $seriousness
}