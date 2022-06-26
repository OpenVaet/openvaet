#!/usr/bin/perl

package cdc;

use strict;
use warnings;
use v5.14;
no autovivification;
use Data::Printer;
use Time::HiRes qw(usleep);
use Exporter; # Gain export capabilities 
use FindBin;
use lib "$FindBin::Bin/../../lib";
use time;

# Exported variables & functions.
our (@EXPORT, @ISA);    # Global variables 
my $minSleepOnAction = 50000;  # Microseconds (0.000001).
my $maxSleepOnAction = 200000;

@ISA    = qw(Exporter); # Take advantage of Exporter's capabilities
@EXPORT = qw(
    $minSleepOnAction
    $maxSleepOnAction
);                      # Exported variables.

sub verify_disclaimer {
    my ($driver) = @_;
    sleep 2;
    my $content = $driver->get_page_source;
    my $tree    = HTML::Tree->new();
    $tree->parse($content);
    if ($tree->look_down(name=>"action-I Agree")) {
        my $acceptDisclaimerButton = $driver->find_element("(//input[\@name='action-I Agree'])[1]");
        $acceptDisclaimerButton->click();
        sleep 2;
    }
}

sub select_event_details {
    my ($driver) = @_;
    my $accessSearch = $driver->find_element("(//input[\@value='VAERS Report Details*'])[2]");
    $accessSearch->click();
    sleep 2;
}

sub select_search_form {
    my ($driver) = @_;
    my $accessSearch = $driver->find_element("(//a[\@title='Show the options form to create a report'])[1]");
    $accessSearch->click();
    sleep 2;
}

sub simulate_typing {
    my ($driver, $elem, $string) = @_;
    $elem->click();
    my $randomSleep = int(rand($maxSleepOnAction));
    $randomSleep = $minSleepOnAction if $randomSleep < $minSleepOnAction;
    usleep($randomSleep);
    my @chars = split '', $string;
    die unless scalar @chars;
    for my $char (@chars) {
        $elem->send_keys($char);
        my $randomSleep = int(rand($maxSleepOnAction));
        $randomSleep = $minSleepOnAction if $randomSleep < $minSleepOnAction;
        usleep($randomSleep);
    }
}

sub cast_event_form {
    my ($driver) = @_;
    my $accessSearch = $driver->find_element("(//input[\@id='submit-button1'])[1]");
    $accessSearch->click();
    sleep 2;
}

sub parse_template_v1 {
    my ($tree) = @_;

    # Fetching classified details.
    my @tables = $tree->look_down(class=>"vrs-rpt");
    # open my $out, '>', 'cdc.html';
    # print $out $tree->as_HTML('<>&', "\t");
    my %stats  = ();
    for my $table (@tables) {
        my @ths = $table->look_down(class=>"vtitle");
        my $tableTitle;
        if (scalar @ths == 1) {
            $tableTitle = $ths[0]->as_trimmed_text;
        } else {
            if (scalar @ths == 7) {
                $tableTitle = 'Vaccines Details';
            } else {
                $tableTitle = 'Symptoms';
            }
        }
        # say "*" x 50;
        # say "tableTitle : $tableTitle";
        # say "*" x 50;
        if ($tableTitle eq 'Event Information' ||
            $tableTitle eq 'Event Categories') {
            my @trs = $table->find('tr');
            my %columnNames = ();
            for my $tr (@trs) {
                my @ths = $tr->find('th');
                my @tds = $tr->find('td');
                next unless scalar @tds;
                my $thNum = 0;
                for my $th (@ths) {
                    my $label = $th->as_trimmed_text;
                    $label =~ s/ //g;
                    my $value = $tds[$thNum]->as_trimmed_text;
                    $stats{$tableTitle}->{$label} = $value;
                    # say "$tableTitle | $label : $value";
                    $thNum++;
                }
            }
        } elsif ($tableTitle eq 'Symptom') {
            my @trs = $table->find('tr');
            my %columnNames = ();
            my $trNum = 0;
            for my $tr (@trs) {
                $trNum++;
                my @tds = $tr->find('td');
                for my $td (@tds) {
                    my $value = $td->as_trimmed_text;
                    $value =~ s/ //g;
                    push @{$stats{$tableTitle}}, $value;
                    # say "$tableTitle | $value";
                }
            }
        } elsif ($tableTitle eq 'Vaccines Details') {
            my @trs    = $table->find('tr');
            my %columnNames = ();
            my $trNum  = 0;
            my %labels = ();
            for my $tr (@trs) {
                # say $tr->as_HTML('<>&', "\t");
                $trNum++;
                if ($trNum == 1) {
                    my @ths = $tr->find('th');
                    my $thNum = 0;
                    for my $th (@ths) {
                        $thNum++;
                        my $value = $th->as_trimmed_text;
                        $value =~ s/ //g;
                        $labels{$thNum} = $value;
                    }
                } else {
                    my @tds = $tr->find('td');
                    my $refNum = $trNum - 1;
                    my $tdNum = 0;
                    for my $td (@tds) {
                        $tdNum++;
                        my $column = $labels{$tdNum} // die;
                        $column =~ s/ //g;
                        my $value  = $td->as_trimmed_text;
                        $stats{$tableTitle}->{$refNum}->{$column} = $value;
                        # say "$tableTitle - $column | $value";
                    }
                }
            }
            # p%stats;
            # c_e();
        } else {
            die "to code : $tableTitle";
        }
        # print $out $table->as_HTML('<>&', "\t");
    }

    # Fetching text details.
    my $adverseEffectDescription;
    my @textFields = $tree->look_down(class=>"vrs-rpt text");
    for my $textField (@textFields) {
        my $title = $textField->look_down(class=>"vtitle");
        $title = $title->as_trimmed_text;
        $title =~ s/ //g;
        if ($title eq 'Adverse Event Description') {
            my $td = $textField->find('td');
            $td = $td->as_trimmed_text;
            # say "title : $title";
            # say "td    : $td";
            $adverseEffectDescription = $td;
        }
    }
    $stats{'Event Information'}->{'Adverse Event Description'} = $adverseEffectDescription;
    # p%stats;
    # die;
    return %stats;
    # close $out;
    # sleep 2;
}

1;