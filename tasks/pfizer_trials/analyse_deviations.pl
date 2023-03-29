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

my $deviationsADFile   = 'public/doc/pfizer_trials/pfizer_addv_patients.json';
my $deviationsSDFile   = 'public/doc/pfizer_trials/pfizer_sddv_patients.json';
my $deviationsSuppFile = 'public/doc/pfizer_trials/pfizer_suppdv_patients.json';
my %deviationsAD       = ();
my %deviationsSD       = ();
my %deviationsSupp     = ();
load_deviations_ad();
load_deviations_sd();
load_supp_deviations();

sub load_deviations_ad {
	open my $in, '<:utf8', $deviationsADFile or die "Missing file [$deviationsADFile]";
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%deviationsAD = %$json;
	say "[$deviationsADFile] -> subjects : " . keys %deviationsAD;
}

sub load_deviations_sd {
	open my $in, '<:utf8', $deviationsSDFile or die "Missing file [$deviationsSDFile]";
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%deviationsSD = %$json;
	say "[$deviationsSDFile] -> subjects : " . keys %deviationsSD;
}

sub load_supp_deviations {
	open my $in, '<:utf8', $deviationsSuppFile or die "Missing file [$deviationsSuppFile]";
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%deviationsSupp = %$json;
	# p%deviationsSupp;die;
	say "[$deviationsSuppFile] -> subjects : " . keys %deviationsSupp;
}

my %deviations     = ();
my %setsAttributed = ();
open my $out, '>:utf8', 'public/doc/pfizer_trials/deviations_data_currated.csv';
say $out "SUBJID;DVSPID;DESGTOR;DVCAT;EPOCH;DVSEQ;SOURCE;ACTSITE;CAPE;DVTERM;DVSTDTC;";
for my $subjectId (sort{$a <=> $b} keys %deviationsSupp) {
	# say "*" x 50;
	# say "subjectId : $subjectId";
	# p$deviationsAD{$subjectId};
	# p$deviationsSD{$subjectId};
	# p$deviationsSupp{$subjectId};
	for my $deviationId (sort keys %{$deviationsAD{$subjectId}}) {
		die unless exists $deviationsSD{$subjectId};
		my $visitDesignator = $deviationsAD{$subjectId}->{$deviationId}->{'visitDesignator'} // die;
		my $epoch           = $deviationsSD{$subjectId}->{$deviationId}->{'epoch'}           // die;
		die unless $deviationsAD{$subjectId}->{$deviationId}->{'deviationDate'} eq $deviationsSD{$subjectId}->{$deviationId}->{'dvDate'};
		die unless $deviationsAD{$subjectId}->{$deviationId}->{'dvSeq'} eq $deviationsSD{$subjectId}->{$deviationId}->{'dvSeq'};
		my $deviationDate   = $deviationsAD{$subjectId}->{$deviationId}->{'deviationDate'}   // die;
		my $dvCat           = $deviationsSD{$subjectId}->{$deviationId}->{'dvCat'}           // die;
		my $dvSeq           = $deviationsSD{$subjectId}->{$deviationId}->{'dvSeq'}           // die;
		($dvSeq)            = split '\.', $dvSeq;
		my $dvTerm          = $deviationsSD{$subjectId}->{$deviationId}->{'dvTerm'}          // die;
		my $cape            = $deviationsAD{$subjectId}->{$deviationId}->{'cape'}            // die;
		my $deviationTerm   = $deviationsAD{$subjectId}->{$deviationId}->{'deviationTerm'}   // die;
		my $deviationCompdate = $deviationDate;
		$deviationCompdate    =~ s/\D//g;
		# die;
		unless (
			keys %{$deviationsSupp{$subjectId}->{$dvSeq}} == 4 ||
			keys %{$deviationsSupp{$subjectId}->{$dvSeq}} == 5
		) {
			p$deviationsSupp{$subjectId}->{$dvSeq};
			die;
		}
		my $designator = $deviationsSupp{$subjectId}->{$dvSeq}->{'DESGTOR'} // die;
		my $setCape    = $deviationsSupp{$subjectId}->{$dvSeq}->{'CAPE'}    // die;
		my $source     = $deviationsSupp{$subjectId}->{$dvSeq}->{'SOURCE'}  // die;
		my $actSite    = $deviationsSupp{$subjectId}->{$dvSeq}->{'ACTSITE'} // die;
		my $dvTerm1    = $deviationsSupp{$subjectId}->{$dvSeq}->{'DVTERM1'} // "";
		if ($visitDesignator ne $designator || $cape ne $setCape) {
			die "missmatch";
			# $setsAttributed{$setNum}   = $deviationId;
			# p$deviationsSupp{$subjectId}->{$setNum};
		}
		die if exists $setsAttributed{$subjectId}->{$dvSeq};
		if ($dvTerm1) {
			$dvTerm .= " $dvTerm1";
		}
		$setsAttributed{$subjectId}->{$dvSeq} = 1;
		$deviations{$subjectId}->{$deviationId}->{'visitDesignator'} = $visitDesignator;
		$deviations{$subjectId}->{$deviationId}->{'deviationDate'} = $deviationDate;
		$deviations{$subjectId}->{$deviationId}->{'dvCat'} = $dvCat;
		$deviations{$subjectId}->{$deviationId}->{'dvTerm'} = $dvTerm;
		$deviations{$subjectId}->{$deviationId}->{'dvSeq'} = $dvSeq;
		$deviations{$subjectId}->{$deviationId}->{'source'} = $source;
		$deviations{$subjectId}->{$deviationId}->{'actSite'} = $actSite;
		$deviations{$subjectId}->{$deviationId}->{'epoch'} = $epoch;
		$deviations{$subjectId}->{$deviationId}->{'cape'} = $cape;
		$deviations{$subjectId}->{$deviationId}->{'dvTerm1'} = $dvTerm1;
		say $out "$subjectId;$deviationId;$visitDesignator;$dvCat;$epoch;$dvSeq;$source;$actSite;$cape;$dvTerm;$deviationDate;";
		# say "visitDesignator : $visitDesignator";
		# say "dvCat           : $dvCat";
		# say "dvTerm          : $dvTerm";
		# say "dvSeq           : $dvSeq";
		# say "epoch           : $epoch";
		# say "designator      : $designator";
		# say "setCape         : $setCape";
		# say "actSite         : $actSite";
		# say "source          : $source";
		# say "setCape        : $setCape";
		# p$deviations{$subjectId}->{$deviationId};
		# die unless $deviationSuppDevSetNumber;
		# die;
	}
	# die;
}
close $out;

# Verify that each set has been attributed.
for my $subjectId (sort{$a <=> $b} keys %deviationsSupp) {
	for my $dvSeq (sort keys %{$deviationsSupp{$subjectId}}) {
		unless (exists $setsAttributed{$subjectId}->{$dvSeq}) {
			say "*" x 50;
			say "subjectId : $subjectId";
			say "dvSeq : $dvSeq";
			die;
		}
	}
}

# Print usable JSON.
open my $out2, '>:utf8', 'public/doc/pfizer_trials/deviations_data_currated.json';
print $out2 encode_json\%deviations;
close $out2;