#!/usr/bin/perl
use strict;
use warnings;
use v5.26;
use Data::Dumper;
use Data::Printer;
binmode STDOUT, ":utf8";
no autovivification;
use utf8;
use JSON;
use Math::Round qw(nearest);
use Math::CDF;
use FindBin;
use lib "$FindBin::Bin/../../lib";
use time;
use Date::WeekNumber qw/ iso_week_number /;
use Scalar::Util qw(looks_like_number);
use time;

# Loading data required.
my $adslFile = 'public/doc/pfizer_trials/pfizer_adsl_patients.json';
my %adsl     = ();
load_adsl();

my %stats    = ();

# Sorts the subjects by original trial site id & subject incremental number.
my %subjectIdsBySites = ();
sort_subjects_by_trial_sites();

# For each site, reviews the offsets between 1001 .. First subject & between subject increments.
my %subjectsIds = ();
detect_missing_subjects();

# Print output (present & missing subjects).
open my $out, '>:utf8', 'subjects_by_sites_incremental_numbers.csv';
say $out "Trial Site Id;Subject Id;Arm;Screening Datetime;Exists;";
for my $trialSiteId (sort{$a <=> $b} keys %subjectsIds) {
	for my $trialSiteSubjectId (sort{$a <=> $b} keys %{$subjectsIds{$trialSiteId}}) {
		my $subjectId = $subjectIdsBySites{$trialSiteId}->{$trialSiteSubjectId} // '';
		my $arm = $adsl{$subjectId}->{'arm'} // '';
		my $screeningDatetime = $adsl{$subjectId}->{'screeningDatetime'} // '';
		my $exists = $subjectsIds{$trialSiteId}->{$trialSiteSubjectId} // die;
		say $out "$trialSiteId;$trialSiteId$trialSiteSubjectId;$arm;$screeningDatetime;$exists;";
	}
}
close $out;

sub sort_subjects_by_trial_sites {
	for my $subjectId (sort{$a <=> $b} keys %adsl) {
		my ($trialSiteId, $trialSiteSubjectId) = $subjectId =~ /^(....)(....)$/;
		die "subjectId : $subjectId" unless $trialSiteId && $trialSiteSubjectId;
		$subjectIdsBySites{$trialSiteId}->{$trialSiteSubjectId} = $subjectId;
	}
}

sub detect_missing_subjects {
	my ($formerSite, $formerId);
	for my $trialSiteId (sort{$a <=> $b} keys %subjectIdsBySites) {
		if ($formerSite && $formerSite ne $trialSiteId) {
			$formerId = undef;
		}
		for my $trialSiteSubjectId (sort{$a <=> $b} keys %{$subjectIdsBySites{$trialSiteId}}) {
			$stats{'parsed'}++;
			if ($formerId) {
				my $theoricalNext =  $formerId + 1;
				unless ($theoricalNext == $trialSiteSubjectId) {
					my $upTo = $trialSiteSubjectId - 1;
					# say "[$trialSiteSubjectId] != $theoricalNext";
					for my $theorical ($theoricalNext .. $upTo) {
						$subjectsIds{$trialSiteId}->{$theorical} = 'Missing';
						say "Missing [$trialSiteId$theorical]";
						$stats{'errors'}++;
					}
				} else {
					# say "Present [$trialSiteId$trialSiteSubjectId]";
					$stats{'asExpected'}++;
				}
			} else {
				unless ($trialSiteSubjectId == 1001) {
					# say "[$trialSiteSubjectId] != 1001";
					my $upTo = $trialSiteSubjectId - 1;
					for my $theorical (1001 .. $upTo) {
						$subjectsIds{$trialSiteId}->{$theorical} = 'Missing';
						say "Missing [$trialSiteId$theorical]";
						$stats{'errors'}++;
					}
				} else {
					# say "Present [$trialSiteId$trialSiteSubjectId]";
					$stats{'asExpected'}++;
				}
			}
			# $subjectsIds{$trialSiteId}->{$trialSiteSubjectId} = 'Present';
			$formerId = $trialSiteSubjectId;
		}
		$formerSite = $trialSiteId;
	}
	p%stats;
}

sub load_adsl {
	open my $in, '<:utf8', $adslFile or die "Missing file [$adslFile]";
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%adsl = %$json;
	say "[$adslFile] -> subjects : " . keys %adsl;
}