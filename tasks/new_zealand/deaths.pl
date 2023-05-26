#!/usr/bin/perl
use strict;
use warnings;
use Statistics::Descriptive;

my %data = (
    2010 => 28437, 2011 => 30081, 2012 => 30099, 2013 => 29568, 2014 => 31062,
    2015 => 31608, 2016 => 31179, 2017 => 33339, 2018 => 33225, 2019 => 34260,
    2020 => 32613, 2021 => 34932, 2022 => 38574
);

my @decade = @data{2010..2019};
my @recent_years = @data{2020..2022};

my $stat = Statistics::Descriptive::Full->new();
$stat->add_data(@decade);
my $decade_stddev = $stat->standard_deviation();

foreach my $year (2020..2022) {
    my $z = ($data{$year} - mean(@decade)) / $decade_stddev;
    print "Z-score for $year: $z\n";
}

sub mean {
    my @data = @_;
    my $total = 0;
    $total += $_ for @data;
    return $total / @data;
}