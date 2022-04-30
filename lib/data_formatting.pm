#!/usr/bin/perl

package data_formatting;

use strict;
use warnings;
use v5.14;
no autovivification;

sub paginate {
    my ($pageNumber,
        $total,
        $pageSize)       = @_;
    my $maxPages         = $total / $pageSize;
    my $intMaxPages      = int($total / $pageSize);
    if ($intMaxPages    != $maxPages) {
        $maxPages        = $intMaxPages + 1;
    }
    my %pages = ();
    if ($maxPages <= 7) {
        for my $pNum (1.. $maxPages) {
            $pages{$pNum} = $pNum;
        }
    } else {
        my $pageMinus   = $pageNumber - 1;
        $pageMinus      = 1 if $pageMinus < 1;
        my $pagePlus    = $pageNumber + 1;
        if ($pageMinus == 1) {
            my $incr = 1;
            for my $iter (1 .. 5) {
                $pages{$incr} = $pageMinus;
                $incr++;
                $pageMinus++;
            }
            $pages{$incr} = '..';
            $incr++;
            $pages{$incr} = $maxPages;
        } elsif ($pagePlus >= $maxPages) {
            $pagePlus = $maxPages;
            $pages{'1'} = 1;
            $pages{'2'} = '..';
            my $incr = 7;
            $pages{$incr} = '..';
            for my $iter (1 .. 5) {
                $pages{$incr} = $pagePlus;
                $incr--;
                $pagePlus--;
            }
        } else {
            $pages{'1'} = 1;
            $pages{'2'} = '..';
            my $incr = 3;
            for my $iter (1 .. 3) {
                $pages{$incr} = $pageMinus;
                $incr++;
                $pageMinus++;
            }
            $pages{$incr} = '..';
            $incr++;
            $pages{$incr} = $maxPages;
        }
    }
    return ($maxPages, %pages);
}

1;