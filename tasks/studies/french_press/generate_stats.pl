#!/usr/bin/perl
use strict;
use warnings;
use v5.30;
use Data::Dumper;
use Data::Printer;
binmode STDOUT, ":utf8";
use utf8;
use JSON;
use FindBin;
use lib "$FindBin::Bin/../../../lib";

# Project's libraries.
use time;

my $folder = "raw_data/libramemoria";

for my $file (glob "$folder/*") {
	say $file;
	my $json;
	open my $in, '<:utf8', $file;
	while (<$in>) {
		chomp $_;
		$json = $_;
	}
	close $in;
	$json = decode_json($json);
	p$json;
	die;
}