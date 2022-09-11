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
use File::Path qw(make_path);
use FindBin;
use lib "$FindBin::Bin/../../lib";

# Project's libraries.
use global;
use time;
use config;

# Defines targeted drug ID.
my %ecdcDrugsFetched = ();
$ecdcDrugsFetched{'1136'} = 1;
$ecdcDrugsFetched{'1137'} = 1;
$ecdcDrugsFetched{'1138'} = 1;
$ecdcDrugsFetched{'1139'} = 1;
$ecdcDrugsFetched{'1140'} = 1;

# Fetches current date.
my $currentDatetime = time::current_datetime();
my ($currentDate)   = split ' ', $currentDatetime;
$currentDate =~ s/\D//g;

# Defines export folder.
my $exportFolder = "edarles/eudravigilance";
make_path($exportFolder) unless -d $exportFolder;

ecdc_notices();

sub ecdc_notices {

    # Fetching drugs.
    # say "fetching drugs ...";
    my %drugs = ();
    my $dTb = $dbh->selectall_hashref("SELECT id as ecdcDrugId, name FROM ecdc_drug", 'ecdcDrugId');
    for my $ecdcDrugId (sort{$a <=> $b} keys %$dTb) {
        my $name = %$dTb{$ecdcDrugId}->{'name'}         // die;
        $drugs{$ecdcDrugId}->{'name'} = $name;
    }

    # Fetching drugs <-> notices relations.
    # say "fetching drugs notices ...";
    my %drugsNotices = ();
    my $dNTb = $dbh->selectall_hashref("SELECT id as ecdcDrugNoticeId, ecdcDrugId, ecdcNoticeId FROM ecdc_drug_notice", 'ecdcDrugNoticeId');
    for my $ecdcDrugNoticeId (keys %$dNTb) {
        my $ecdcDrugId   = %$dNTb{$ecdcDrugNoticeId}->{'ecdcDrugId'}   // die;
        my $ecdcNoticeId = %$dNTb{$ecdcDrugNoticeId}->{'ecdcNoticeId'} // die;
        $drugsNotices{$ecdcNoticeId}->{$ecdcDrugId} = 1;
    }

    # Fetching reactions.
    # say "fetching reactions ...";
    my %reactions = ();
    my $rTb = $dbh->selectall_hashref("SELECT id as ecdcReactionId, name FROM ecdc_reaction", 'ecdcReactionId');
    %reactions = %$rTb;

    # Fetching reactions outcomes.
    # say "fetching drugs outcomes ...";
    my %reactionsOutcomes = ();
    my $rOTb = $dbh->selectall_hashref("SELECT id as ecdcReactionOutcomeId, name FROM ecdc_reaction_outcome", 'ecdcReactionOutcomeId');
    %reactionsOutcomes = %$rOTb;

    # Fetching notices <-> reactions relations.
    my %noticeReactions = ();
    # say "fetching notices reactions ...";
    my $nRtb = $dbh->selectall_hashref("SELECT id as ecdcNoticeReactionId, ecdcNoticeId, ecdcReactionId, ecdcReactionOutcomeId FROM ecdc_notice_reaction", 'ecdcNoticeReactionId');
    for my $ecdcNoticeReactionId (sort{$a <=> $b} keys %$nRtb) {
        my $ecdcNoticeId          = %$nRtb{$ecdcNoticeReactionId}->{'ecdcNoticeId'}          // die;
        my $ecdcReactionId        = %$nRtb{$ecdcNoticeReactionId}->{'ecdcReactionId'}        // die;
        my $ecdcReactionOutcomeId = %$nRtb{$ecdcNoticeReactionId}->{'ecdcReactionOutcomeId'} // die;
        $noticeReactions{$ecdcNoticeId}->{$ecdcReactionId}->{'ecdcNoticeReactionId'} = $ecdcNoticeReactionId;
        $noticeReactions{$ecdcNoticeId}->{$ecdcReactionId}->{'ecdcReactionOutcomeId'} = $ecdcReactionOutcomeId;
    }

    # Fetching notices.
    my $sql                    = "
        SELECT
            ecdc_notice.id as ecdcNoticeId,
            internalId as eudraVigilanceId,
            ICSRUrl as url,
            receiptTimestamp,
            ecdcSexId,
            ecdc_sex.name as ecdcSexName,
            pdfPath,
            ecdcSeriousness,
            ecdcReporterType,
            formSeriousness,
            formReporterType,
            ecdcGeographicalOrigin,
            ecdcYearId,
            ecdcAgeGroup,
            ecdc_year.name as ecdcYearName
        FROM ecdc_notice
            LEFT JOIN ecdc_year ON ecdc_year.id = ecdc_notice.ecdcYearId
            LEFT JOIN ecdc_sex  ON ecdc_sex.id  = ecdc_notice.ecdcSexId";
    say $sql;
    my $tb        = $dbh->selectall_hashref($sql, 'ecdcNoticeId');
    open my $out, '>:utf8', "$exportFolder/deaths_notices.csv";
    say $out "eudravigilanceId;receiptDate;seriousness;reporterType;sex;ageGroup;url;reactions;";
    for my $ecdcNoticeId (sort{$a <=> $b} keys %$tb) {
        next unless keys %{$drugsNotices{$ecdcNoticeId}}; # Happens when we are indexing notices live only.
        my ($hasSearchedDrug, $hasSearchedOutcome, $hasSearchedReaction) = (0, 0, 0);
        for my $ecdcDrugId (sort{$a <=> $b} keys %{$drugsNotices{$ecdcNoticeId}}) {
            $hasSearchedDrug = 1 if exists $ecdcDrugsFetched{$ecdcDrugId};
        }
        next unless $hasSearchedDrug;
        my $eudraVigilanceId             = %$tb{$ecdcNoticeId}->{'eudraVigilanceId'}                   // die;
        my $url                          = %$tb{$ecdcNoticeId}->{'url'}                                // die;
        my $ecdcSeriousness              = %$tb{$ecdcNoticeId}->{'ecdcSeriousness'}                    // die;
        my $ecdcSeriousnessName          = $enums{'ecdcSeriousness'}->{$ecdcSeriousness}               // die;
        my $ecdcReporterType             = %$tb{$ecdcNoticeId}->{'ecdcReporterType'}                   // die;
        my $ecdcReporterTypeName         = $enums{'ecdcReporterType'}->{$ecdcReporterType}             // die;
        my $ecdcGeographicalOrigin       = %$tb{$ecdcNoticeId}->{'ecdcGeographicalOrigin'}             // die;
        my $ecdcGeographicalOriginName   = $enums{'ecdcGeographicalOrigin'}->{$ecdcGeographicalOrigin} // die;
        my $ecdcYearId                   = %$tb{$ecdcNoticeId}->{'ecdcYearId'}                         // die;
        my $ecdcAgeGroup                 = %$tb{$ecdcNoticeId}->{'ecdcAgeGroup'}                       // die;
        my $ecdcAgeGroupName             = $enums{'ecdcAgeGroup'}->{$ecdcAgeGroup}                     // die;
        my $ecdcYearName                 = %$tb{$ecdcNoticeId}->{'ecdcYearName'}                       // die;
        my $ecdcSexName                  = %$tb{$ecdcNoticeId}->{'ecdcSexName'}                        // die;
        my $receiptTimestamp             = %$tb{$ecdcNoticeId}->{'receiptTimestamp'}                   // die;
        my $receiptDatetime              = time::timestamp_to_datetime($receiptTimestamp);
        my ($receiptDate)                = split ' ', $receiptDatetime;
        my %obj  = ();
        $obj{'eudraVigilanceId'}           = $eudraVigilanceId;
        $obj{'ecdcYearName'}               = $ecdcYearName;
        $obj{'receiptDate'}                = $receiptDate;
        $obj{'ecdcSexName'}                = $ecdcSexName;
        $obj{'ecdcAgeGroupName'}           = $ecdcAgeGroupName;
        $obj{'ecdcSeriousnessName'}        = $ecdcSeriousnessName;
        $obj{'ecdcReporterTypeName'}       = $ecdcReporterTypeName;
        $obj{'ecdcGeographicalOriginName'} = $ecdcGeographicalOriginName;
        $obj{'url'}                        = $url;

        # Incrementing related substances.
        for my $ecdcDrugId (sort{$a <=> $b} keys %{$drugsNotices{$ecdcNoticeId}}) {
            my $ecdcDrugName = $drugs{$ecdcDrugId}->{'name'} // die;
            my %dObj = ();
            $dObj{'name'} = $ecdcDrugName;
            push @{$obj{'substances'}}, \%dObj;
        }

        # Incrementing related reactions.
        my $reactions;
        for my $ecdcReactionId (sort{$a <=> $b} keys %{$noticeReactions{$ecdcNoticeId}}) {
            my $ecdcReactionOutcomeId = $noticeReactions{$ecdcNoticeId}->{$ecdcReactionId}->{'ecdcReactionOutcomeId'} // die;
            my $ecdcReactionName = $reactions{$ecdcReactionId}->{'name'} // die;
            my $ecdcReactionOutcomeName = $reactionsOutcomes{$ecdcReactionOutcomeId}->{'name'} // die;
            $hasSearchedReaction = 1 if $ecdcReactionOutcomeName eq 'Fatal';
            my %rObj = ();
            $rObj{'name'} = $ecdcReactionName;
            $rObj{'outcome'} = $ecdcReactionOutcomeName;
            push @{$obj{'reactions'}}, \%rObj;
            die "about to miss .csv export" if $ecdcReactionName =~ /,/;
            die "about to miss .csv export" if $ecdcReactionOutcomeName =~ /,/;
            $reactions .= ", $ecdcReactionName | $ecdcReactionOutcomeName" if $reactions;
            $reactions = "$ecdcReactionName | $ecdcReactionOutcomeName" unless $reactions;
        }
        next unless $hasSearchedReaction;
        # push @ecdcNotices, \%obj;

        # Verifying values prior to .Csv export.
        my @values = ($eudraVigilanceId, $receiptDate, $ecdcSeriousnessName, $ecdcReporterTypeName, $ecdcSexName, $ecdcAgeGroupName, $url);
        for my $value (@values) {
        	die "about to miss .csv export - 2" if $value =~ /;/;
        }


        say $out "$eudraVigilanceId;$receiptDate;$ecdcSeriousnessName;$ecdcReporterTypeName;$ecdcSexName;$ecdcAgeGroupName;$url;$reactions;";
        # p%obj;
        # die;
    }
    close $out;
}