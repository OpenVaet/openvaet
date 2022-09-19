#!/usr/bin/perl
use strict;
use warnings;
use 5.30.0;
binmode STDOUT, ":utf8";
use utf8;

# Cpan dependencies.
no autovivification;
use Data::Printer;
use Data::Dumper;
use JSON;
use HTTP::Cookies;
use HTML::Tree;
use LWP::UserAgent;
use LWP::Simple;
use File::Path qw(make_path);
use HTTP::Cookies qw();
use HTTP::Request::Common qw(POST OPTIONS);
use HTTP::Headers;
use Hash::Merge;
use Scalar::Util qw(looks_like_number);
use Digest::MD5  qw(md5 md5_hex md5_base64);

# Project's libraries.
use FindBin;
use lib "$FindBin::Bin/../../lib";
use time;
use global;
use country;

my %symptoms = ();
my $latestSymptomId = 0;
symptoms();

sub symptoms {
	my $tb = $dbh->selectall_hashref("SELECT id as symptomId, name as symptomName FROM symptom WHERE id > $latestSymptomId", 'symptomId');
	for my $symptomId (sort{$a <=> $b} keys %$tb) {
		$latestSymptomId = $symptomId;
		my $symptomName = lc %$tb{$symptomId}->{'symptomName'} // die;
		$symptoms{$symptomName}->{'symptomId'} = $symptomId;
	}
}

my %symptomsSets = ();
vaers_fertility_symptoms();
aus_symptoms();

sub vaers_fertility_symptoms {
	my $tb = $dbh->selectall_hashref("SELECT name, discarded, pregnancyRelated, severePregnancyRelated, menstrualDisorderRelated, foetalDeathRelated FROM vaers_fertility_symptom", 'name');
	for my $symptomName (sort keys %$tb) {
		my $symptomNameNormalized = lc $symptomName;
		my $discarded = %$tb{$symptomName}->{'discarded'} // die;
		my $pregnancyRelated = %$tb{$symptomName}->{'pregnancyRelated'} // die;
		my $severePregnancyRelated = %$tb{$symptomName}->{'severePregnancyRelated'} // die;
		my $menstrualDisorderRelated = %$tb{$symptomName}->{'menstrualDisorderRelated'} // die;
		my $foetalDeathRelated = %$tb{$symptomName}->{'foetalDeathRelated'} // die;
		$discarded = unpack("N", pack("B32", substr("0" x 32 . $discarded, -32)));
		$pregnancyRelated = unpack("N", pack("B32", substr("0" x 32 . $pregnancyRelated, -32)));
		$severePregnancyRelated = unpack("N", pack("B32", substr("0" x 32 . $severePregnancyRelated, -32)));
		$menstrualDisorderRelated = unpack("N", pack("B32", substr("0" x 32 . $menstrualDisorderRelated, -32)));
		$foetalDeathRelated = unpack("N", pack("B32", substr("0" x 32 . $foetalDeathRelated, -32)));
		if ($discarded) {
			$symptomsSets{'Indicators of Administration Errors'}->{$symptomNameNormalized} = 1;
		}
		if ($pregnancyRelated) {
			$symptomsSets{'Pregnancy Related'}->{$symptomNameNormalized} = 1;
		}
		if ($severePregnancyRelated) {
			$symptomsSets{'Pregnancy Complications Related'}->{$symptomNameNormalized} = 1;
		}
		if ($menstrualDisorderRelated) {
			$symptomsSets{'Menstrual Disorders Related'}->{$symptomNameNormalized} = 1;
		}
		if ($foetalDeathRelated) {
			$symptomsSets{'Foetal Deaths Related'}->{$symptomNameNormalized} = 1;
		}
		if ($discarded || $pregnancyRelated || $severePregnancyRelated || $menstrualDisorderRelated || $foetalDeathRelated) {
			unless (exists $symptoms{$symptomNameNormalized}->{'symptomId'}) {
				my $sth = $dbh->prepare("INSERT INTO symptom (name) VALUES (?)");
				$sth->execute($symptomName) or die $sth->err();
				symptoms();
			}	
		}
	}
}

sub aus_symptoms {
	my $tb = $dbh->selectall_hashref("SELECT name, active FROM aus_symptom", 'name');
	for my $symptomName (sort keys %$tb) {
		my $symptomNameNormalized = lc $symptomName;
		my $active = %$tb{$symptomName}->{'active'} // die;
		$active = unpack("N", pack("B32", substr("0" x 32 . $active, -32)));
		if ($active) {
			$symptomsSets{'Anaphylaxis symptoms'}->{$symptomNameNormalized} = 1;
		}
		if ($active) {
			unless (exists $symptoms{$symptomNameNormalized}->{'symptomId'}) {
				my $sth = $dbh->prepare("INSERT INTO symptom (name) VALUES (?)");
				$sth->execute($symptomName) or die $sth->err();
			}	
		}
	}
}

for my $symptomSetName (sort keys %symptomsSets) {
	my @symptoms = ();
	for my $symptomName (sort keys %{$symptomsSets{$symptomSetName}}) {
		my $symptomId = $symptoms{$symptomName}->{'symptomId'} // die;
		push @symptoms, $symptomId;
	}
	my $symptoms = encode_json\@symptoms;
	my $sth = $dbh->prepare("INSERT INTO symptoms_set (name, symptoms, userId) VALUES (?, ?, ?)");
	if ($symptomSetName ne 'Anaphylaxis symptoms') {
		$sth->execute($symptomSetName, $symptoms, 1) or die $sth->err();
	} else {
		$sth->execute($symptomSetName, $symptoms, 2) or die $sth->err();
	}
}