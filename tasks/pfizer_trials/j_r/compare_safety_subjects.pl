#!/usr/bin/perl
use strict;
use warnings;
use v5.26;
use Data::Dumper;
use Data::Printer;
binmode STDOUT, ":utf8";
use utf8;
use open ':std', ':encoding(UTF-8)';
no autovivification;
use utf8;

my $f1 = 'tasks/pfizer_trials/j_r/per_adrg_safety.csv';
my $f2 = 'tasks/pfizer_trials/j_r/per_interface_satefy.csv';

my %f1 = ();
my %f2 = ();

load_f1();

load_f2();

sub load_f1 {
	open my $in, '<:utf8', $f1;
	while (<$in>) {
		chomp $_;
		my ($subjid) = split ';', $_;
		next if $subjid eq 'subjid';
		$f1{$subjid} = 1;
	}
	close $in;
}

sub load_f2 {
	open my $in, '<:utf8', $f2;
	while (<$in>) {
		chomp $_;
		my ($subjid) = split ';', $_;
		next if $subjid eq 'subjid';
		$f2{$subjid} = 1;
	}
	close $in;
}

# Checking if everyone in F2 is in F1.
for my $subjid (sort{$a <=> $b} keys %f2) {
	unless (exists $f1{$subjid}) {
		die;
	}
}

# Identifying the one guy who shouldn't be in their list.
for my $subjid (sort{$a <=> $b} keys %f1) {
	unless (exists $f2{$subjid}) {
		say "Shouldn't be in safety : [$subjid]";
	}
}