package OpenVaet::Controller::Ecdc;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Log;
use JSON;
use Data::Printer;
use Math::Round qw(nearest);
use FindBin;
use lib "$FindBin::Bin/../lib";
use time;
use data_formatting;
use session;

sub ecdc {
    my $self = shift;
    my $currentLanguage = $self->param('currentLanguage') // 'en';
    my %config          = %{$self->config()};
    my $environment     = $config{'environment'} // die;

    # Loggin session if unknown.
    session::session_from_self($self);

    my $ecdcSourceId             = 1;
    my $sTb                      = $self->dbh->selectrow_hashref("SELECT indexUpdateTimestamp, fullDrugsUpdateTimestamp, totalReports FROM source WHERE id = $ecdcSourceId", undef);
    my ($indexUpdateDatetime, $fullDrugsUpdateDatetime);
    my $totalReports = 0;
    if ($sTb) {
        # p$sTb;
        my $indexUpdateTimestamp     = %$sTb{'indexUpdateTimestamp'};
        my $fullDrugsUpdateTimestamp = %$sTb{'fullDrugsUpdateTimestamp'};
        $totalReports                = %$sTb{'totalReports'} // die;
        $indexUpdateDatetime         = time::timestamp_to_datetime($indexUpdateTimestamp);
    }

    my $ecdcTotalSubstances       = 0;
    if ($indexUpdateDatetime) {
        my $eDTb                  = $self->dbh->selectrow_hashref("SELECT count(id) as ecdcTotalSubstances FROM ecdc_drug", undef);
        $ecdcTotalSubstances      = %$eDTb{'ecdcTotalSubstances'} // die;
    }

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    $self->render(
        environment              => $environment,
        ecdcTotalSubstances      => $ecdcTotalSubstances,
        totalReports             => $totalReports,
        indexUpdateDatetime      => $indexUpdateDatetime,
        fullDrugsUpdateDatetime  => $fullDrugsUpdateDatetime,
        currentLanguage          => $currentLanguage,
        languages                => \%languages
    );
}

sub substances {
    my $self = shift;
    my $currentLanguage = $self->param('currentLanguage') // 'en';
    my %config          = %{$self->config()};
    my $environment     = $config{'environment'} // die;
    # say "environment : $environment";

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    $self->render(
        environment              => $environment,
        currentLanguage          => $currentLanguage,
        languages                => \%languages
    );

}

sub load_substances {
    my $self = shift;
    my $currentLanguage = $self->param('currentLanguage') // 'en';
    my $indexedOnly     = $self->param('indexedOnly')     // die;
    my %config          = %{$self->config()};
    my $environment     = $config{'environment'}          // die;
    # say "environment : $environment";
    # say "indexedOnly : $indexedOnly";

    my @ecdcDrugs = ();

    my $currentDatetime = time::current_datetime();
    my ($currentYear)   = split '-', $currentDatetime;

    my $sql = "
        SELECT
            ecdc_drug.id as ecdcDrugId,
            ecdc_drug.name,
            ecdc_drug.url,
            ecdc_drug.isIndexed,
            ecdc_drug.scrappingTimestamp,
            ecdc_drug.ecsApproval,
            ecdc_drug.updateTimestamp,
            ecdc_drug.totalCasesDisplayed,
            ecdc_drug.totalCasesScrapped,
            ecdc_year.name as earliestAEYear,
            ecdc_drug.aeFromEcdcYearId,
            ecdc_drug.earliestAERTimestamp
        FROM ecdc_drug
            LEFT JOIN ecdc_year ON ecdc_year.id = ecdc_drug.aeFromEcdcYearId";
    if ($indexedOnly eq 'true') {
        $sql .= " WHERE isIndexed = 1";
    }
    my $tb = $self->dbh->selectall_hashref($sql, 'ecdcDrugId');
    for my $ecdcDrugId (sort{$a <=> $b} keys %$tb) {
        my $name                 = %$tb{$ecdcDrugId}->{'name'}         // die;
        my $url                  = %$tb{$ecdcDrugId}->{'url'}          // die;
        my $totalCasesDisplayed  = %$tb{$ecdcDrugId}->{'totalCasesDisplayed'} // die;
        my $totalCasesScrapped   = %$tb{$ecdcDrugId}->{'totalCasesScrapped'}  // 0;
        my $ecsApproval          = %$tb{$ecdcDrugId}->{'ecsApproval'}  // die;
        $ecsApproval             = unpack("N", pack("B32", substr("0" x 32 . $ecsApproval, -32)));
        my $isIndexed            = %$tb{$ecdcDrugId}->{'isIndexed'}  // die;
        $isIndexed               = unpack("N", pack("B32", substr("0" x 32 . $isIndexed, -32)));
        if ($ecsApproval         == 1) {
            $ecsApproval         = 'yes';
        } else {
            $ecsApproval         = 'no';
        }
        my $earliestAEYear       = %$tb{$ecdcDrugId}->{'earliestAEYear'};
        my $scrappingTimestamp   = %$tb{$ecdcDrugId}->{'scrappingTimestamp'};
        my $updateTimestamp      = %$tb{$ecdcDrugId}->{'updateTimestamp'};
        my $earliestAERTimestamp = %$tb{$ecdcDrugId}->{'earliestAERTimestamp'};
        my ($scrappingDatetime,
            $earliestAERDatetime,
            $earliestAERDate)    = ('', undef, '');
        if ($scrappingTimestamp) {
            $scrappingDatetime   = time::timestamp_to_datetime($scrappingTimestamp);
        }
        if ($earliestAERTimestamp) {
            $earliestAERDatetime  = time::timestamp_to_datetime($earliestAERTimestamp);
            ($earliestAERDate)    = split ' ', $earliestAERDatetime;
        }
        my %obj  = ();
        if ($earliestAERTimestamp) {
            my $updateDatetime     = time::timestamp_to_datetime($updateTimestamp);
            my $minutesDifference  = time::calculate_minutes_difference($earliestAERDatetime, $updateDatetime);
            my $daysDifference     = $minutesDifference / 1440;
            my $casesYearlyAverage = nearest(0.01, ($totalCasesDisplayed / $daysDifference * 365));
            # say "$earliestAERDatetime -> $updateDatetime - ($totalCasesDisplayed / $daysDifference ($minutesDifference) * 365) -> $casesYearlyAverage";
            $obj{'casesYearlyAverage'} = $casesYearlyAverage;
        }
        $obj{'name'}                = $name;
        $obj{'isIndexed'}           = $isIndexed;
        $obj{'ecdcDrugId'}          = $ecdcDrugId;
        $obj{'earliestAEYear'}      = $earliestAEYear;
        $obj{'earliestAERDate'}     = $earliestAERDate;
        $obj{'scrappingDatetime'}   = $scrappingDatetime;
        $obj{'ecsApproval'}         = $ecsApproval;
        $obj{'totalCasesDisplayed'} = $totalCasesDisplayed;
        $obj{'totalCasesScrapped'}  = $totalCasesScrapped;
        $obj{'url'}                 = $url;
        push @ecdcDrugs, \%obj;
    }


    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    $self->render(
        environment              => $environment,
        currentLanguage          => $currentLanguage,
        ecdcDrugs                => \@ecdcDrugs,
        languages                => \%languages
    );
}

sub set_ecdc_drug_indexation {
    my $self = shift;

    my $isIndexed   = $self->param('isIndexed')  // die;
    my $ecdcDrugId  = $self->param('ecdcDrugId') // die;
    my %config      = %{$self->config()};
    my $environment = $config{'environment'} // die;

    # say "ecdcDrugId : $ecdcDrugId";
    # say "isIndexed  : $isIndexed";

    if ($environment eq 'local') {
        my $sth = $self->dbh->prepare("UPDATE ecdc_drug SET isIndexed = $isIndexed WHERE id = $ecdcDrugId");
        $sth->execute() or die $sth->err();
    }

    $self->render(text => 'ok');
}

sub substance_details {
    my $self = shift;
    my $currentLanguage = $self->param('currentLanguage') // 'en';

    # Loggin session if unknown.
    session::session_from_self($self);

    my $ecdcDrugId = $self->param('ecdcDrugId') // die;
    my $eDTb = $self->dbh->selectrow_hashref("SELECT name as ecdcDrugName, url as ecdcDrugUrl, overviewStats FROM ecdc_drug WHERE id = $ecdcDrugId", undef);
    my $ecdcDrugName = %$eDTb{'ecdcDrugName'} // die;
    my $ecdcDrugUrl = %$eDTb{'ecdcDrugUrl'} // die;
    my $overviewStats = %$eDTb{'overviewStats'};
    if ($overviewStats) {
        $overviewStats = decode_json($overviewStats);
        # p$overviewStats;
    }
    my %enums = %{$self->enums()};
    # say "ecdcDrugId   : $ecdcDrugId";
    # say "ecdcDrugName : $ecdcDrugName";
    # say "ecdcDrugUrl  : $ecdcDrugUrl";

    my $eDYSTb = $self->dbh->selectall_hashref("
        SELECT
            ecdc_drug_year_seriousness.id as ecdcDrugYearSeriousnessId,
            ecdc_drug_year_seriousness.ecdcYearId,
            ecdc_year.name as ecdcYearName,
            ecdc_drug_year_seriousness.ecdcSeriousness,
            ecdc_drug_year_seriousness.totalCases,
            ecdc_drug_year_seriousness.updateTimestamp
        FROM ecdc_drug_year_seriousness
            LEFT JOIN ecdc_year ON ecdc_year.id = ecdc_drug_year_seriousness.ecdcYearId
        WHERE ecdcDrugId = $ecdcDrugId
    ", 'ecdcDrugYearSeriousnessId');
    my %ecdcDrugYearSeriousnesses = ();
    for my $ecdcDrugYearSeriousnessId (sort{$a <=> $b} keys %$eDYSTb) {
        my $ecdcYearName        = %$eDYSTb{$ecdcDrugYearSeriousnessId}->{'ecdcYearName'}    // die;
        my $ecdcSeriousness     = %$eDYSTb{$ecdcDrugYearSeriousnessId}->{'ecdcSeriousness'} // die;
        my $ecdcSeriousnessName = $enums{'ecdcSeriousness'}->{$ecdcSeriousness}             // die;
        my $totalCases          = %$eDYSTb{$ecdcDrugYearSeriousnessId}->{'totalCases'}      // die;
        my $updateTimestamp     = %$eDYSTb{$ecdcDrugYearSeriousnessId}->{'updateTimestamp'} // die;
        my $updateDatetime      = time::timestamp_to_datetime($updateTimestamp);
        say "$ecdcYearName - $ecdcSeriousnessName - $totalCases - $updateDatetime";
        $ecdcDrugYearSeriousnesses{$ecdcYearName}->{$ecdcSeriousness}->{'ecdcSeriousnessName'} = $ecdcSeriousnessName;
        $ecdcDrugYearSeriousnesses{$ecdcYearName}->{$ecdcSeriousness}->{'totalCases'}          = $totalCases;
        $ecdcDrugYearSeriousnesses{$ecdcYearName}->{$ecdcSeriousness}->{'updateDatetime'}      = $updateDatetime;
    }

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    $self->render(
        ecdcDrugYearSeriousnesses => \%ecdcDrugYearSeriousnesses,
        ecdcDrugId                => $ecdcDrugId,
        ecdcDrugName              => $ecdcDrugName,
        ecdcDrugUrl               => $ecdcDrugUrl,
        currentLanguage           => $currentLanguage,
        languages                 => \%languages
    );
}

sub notices {
    my $self = shift;
    my $currentLanguage = $self->param('currentLanguage') // 'en';
    my %config          = %{$self->config()};
    my $environment     = $config{'environment'} // die;

    # Loggin session if unknown.
    session::session_from_self($self);
    
    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    $self->render(
        environment     => $environment,
        currentLanguage => $currentLanguage,
        languages       => \%languages
    );
}

sub load_notices_filters {
    my $self = shift;

    my %enums = %{$self->enums()};
    # p%enums;
    my %forms = ();
    # Listing filters inherited from enums.
    for my $ecdcSeriousness (sort keys %{$enums{'ecdcSeriousness'}}) {
        my $ecdcSeriousnessName = $enums{'ecdcSeriousness'}->{$ecdcSeriousness} // die;
        $forms{'ecdcSeriousness'}->{$ecdcSeriousnessName} = $ecdcSeriousness;
    }
    for my $ecdcReporterType (sort keys %{$enums{'ecdcReporterType'}}) {
        my $ecdcReporterTypeName = $enums{'ecdcReporterType'}->{$ecdcReporterType} // die;
        $forms{'ecdcReporterType'}->{$ecdcReporterTypeName} = $ecdcReporterType;
    }
    for my $ecdcGeographicalOrigin (sort keys %{$enums{'ecdcGeographicalOrigin'}}) {
        my $ecdcGeographicalOriginName = $enums{'ecdcGeographicalOrigin'}->{$ecdcGeographicalOrigin} // die;
        $forms{'ecdcGeographicalOrigin'}->{$ecdcGeographicalOriginName} = $ecdcGeographicalOrigin;
    }
    for my $ecdcAgeGroup (sort keys %{$enums{'ecdcAgeGroup'}}) {
        my $ecdcAgeGroupName = $enums{'ecdcAgeGroup'}->{$ecdcAgeGroup} // die;
        $forms{'ecdcAgeGroup'}->{$ecdcAgeGroup} = $ecdcAgeGroupName;
    }

    # Listing sexes stored.
    my $eSTb = $self->dbh->selectall_hashref("SELECT id as ecdcSexId, name as ecdcSexName FROM ecdc_sex", 'ecdcSexId');
    for my $ecdcSexId (sort{$a <=> $b} keys %$eSTb) {
        my $ecdcSexName = %$eSTb{$ecdcSexId}->{'ecdcSexName'} // die;
        $forms{'ecdcSex'}->{$ecdcSexId} = $ecdcSexName;
    }

    # Listing years stored.
    my $eYTb = $self->dbh->selectall_hashref("SELECT id as ecdcYearId, name as ecdcYearName FROM ecdc_year", 'ecdcYearId');
    for my $ecdcYearId (sort{$a <=> $b} keys %$eYTb) {
        my $ecdcYearName = %$eYTb{$ecdcYearId}->{'ecdcYearName'} // die;
        next if $ecdcYearName == 1900;
        $forms{'ecdcYear'}->{$ecdcYearName} = $ecdcYearId;
    }

    # Listing drugs stored.
    my $eDTb = $self->dbh->selectall_hashref("SELECT id as ecdcDrugId, name FROM ecdc_drug WHERE totalCasesDisplayed != 0", 'ecdcDrugId');
    for my $ecdcDrugId (sort{$a <=> $b} keys %$eDTb) {
        my $name = %$eDTb{$ecdcDrugId}->{'name'} // die;
        $forms{'ecdcDrug'}->{$name} = $ecdcDrugId;
    }

    # Listing reactions stored.
    my $eRTb = $self->dbh->selectall_hashref("SELECT id as ecdcReactionId, name FROM ecdc_reaction", 'ecdcReactionId');
    for my $ecdcReactionId (sort{$a <=> $b} keys %$eRTb) {
        my $name = %$eRTb{$ecdcReactionId}->{'name'} // die;
        $forms{'ecdcReaction'}->{$name} = $ecdcReactionId;
    }

    # Listing outcomes stored.
    my $eROTb = $self->dbh->selectall_hashref("SELECT id as ecdcReactionOutcomeId, name FROM ecdc_reaction_outcome", 'ecdcReactionOutcomeId');
    for my $ecdcReactionOutcomeId (sort{$a <=> $b} keys %$eROTb) {
        my $name = %$eROTb{$ecdcReactionOutcomeId}->{'name'} // die;
        $forms{'ecdcReactionOutcome'}->{$name} = $ecdcReactionOutcomeId;
    }

    $self->render(
        forms => \%forms
    );
}

sub load_notices {
    my $self                     = shift;
    my %enums                    = %{$self->enums()};
    my $pageNumber               = $self->param('pageNumber') // die;
    my $ecdcYear                 = $self->param('ecdcYear');
    my $ecdcDrug                 = $self->param('ecdcDrug');
    my $ecdcSex                  = $self->param('ecdcSex');
    my $noticeSearch             = $self->param('noticeSearch');
    my $ecdcReaction             = $self->param('ecdcReaction');
    my $ecdcAgeGroup             = $self->param('ecdcAgeGroup');
    my $ecdcGeographicalOrigin   = $self->param('ecdcGeographicalOrigin');
    my $ecdcSeriousness          = $self->param('ecdcSeriousness');
    my $ecdcReporterType         = $self->param('ecdcReporterType');
    my $ecdcReactionOutcome      = $self->param('ecdcReactionOutcome');
    my $covidVaccinesOnly        = $self->param('covidVaccinesOnly');
    my @ecdcNotices              = ();
    # say "ecdcGeographicalOrigin : $ecdcGeographicalOrigin";

    # Fetching drugs.
    # say "fetching drugs ...";
    my %drugs = ();
    my $dTb = $self->dbh->selectall_hashref("SELECT id as ecdcDrugId, name FROM ecdc_drug", 'ecdcDrugId');
    for my $ecdcDrugId (sort{$a <=> $b} keys %$dTb) {
        my $name = %$dTb{$ecdcDrugId}->{'name'}         // die;
        $drugs{$ecdcDrugId}->{'name'} = $name;
    }

    # Fetching drugs <-> notices relations.
    # say "fetching drugs notices ...";
    my %drugsNotices = ();
    my $dNTb = $self->dbh->selectall_hashref("SELECT id as ecdcDrugNoticeId, ecdcDrugId, ecdcNoticeId FROM ecdc_drug_notice", 'ecdcDrugNoticeId');
    for my $ecdcDrugNoticeId (keys %$dNTb) {
        my $ecdcDrugId   = %$dNTb{$ecdcDrugNoticeId}->{'ecdcDrugId'}   // die;
        my $ecdcNoticeId = %$dNTb{$ecdcDrugNoticeId}->{'ecdcNoticeId'} // die;
        $drugsNotices{$ecdcNoticeId}->{$ecdcDrugId} = 1;
    }

    # Fetching reactions.
    # say "fetching reactions ...";
    my %reactions = ();
    my $rTb = $self->dbh->selectall_hashref("SELECT id as ecdcReactionId, name FROM ecdc_reaction", 'ecdcReactionId');
    %reactions = %$rTb;

    # Fetching reactions outcomes.
    # say "fetching drugs outcomes ...";
    my %reactionsOutcomes = ();
    my $rOTb = $self->dbh->selectall_hashref("SELECT id as ecdcReactionOutcomeId, name FROM ecdc_reaction_outcome", 'ecdcReactionOutcomeId');
    %reactionsOutcomes = %$rOTb;

    # Fetching notices <-> reactions relations.
    my %noticeReactions = ();
    # say "fetching notices reactions ...";
    my $nRtb = $self->dbh->selectall_hashref("SELECT id as ecdcNoticeReactionId, ecdcNoticeId, ecdcReactionId, ecdcReactionOutcomeId FROM ecdc_notice_reaction", 'ecdcNoticeReactionId');
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
            internalId as name,
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
    if ($ecdcYear || $ecdcSex || $ecdcAgeGroup || $noticeSearch|| $ecdcGeographicalOrigin || $ecdcReporterType || $ecdcSeriousness) {
        $sql .= " WHERE "
    }
    my $hasCondition = 0;
    if ($ecdcYear) {
        $hasCondition = 1;
        $sql .= " ecdcYearId = $ecdcYear";
    }
    if ($ecdcSex) {
        $hasCondition = 1;
        $sql .= " ecdcSexId = $ecdcSex";
    }
    if ($ecdcSeriousness) {
        $sql .= " AND " if $hasCondition == 1;
        $hasCondition = 1;
        $sql .= " ecdcSeriousness = $ecdcSeriousness";
    }
    if ($ecdcReporterType) {
        $sql .= " AND " if $hasCondition == 1;
        $hasCondition = 1;
        $sql .= " ecdcReporterType = $ecdcReporterType";
    }
    if ($ecdcGeographicalOrigin) {
        $sql .= " AND " if $hasCondition == 1;
        $hasCondition = 1;
        $sql .= " ecdcGeographicalOrigin = $ecdcGeographicalOrigin";
    }
    if ($noticeSearch) {
        $sql .= " AND " if $hasCondition == 1;
        $hasCondition = 1;
        $sql .= " ecdc_notice.internalId = '$noticeSearch'";
    }
    if ($ecdcAgeGroup) {
        $sql .= " AND " if $hasCondition == 1;
        $hasCondition = 1;
        $sql .= " ecdcAgeGroup = $ecdcAgeGroup";
    }
    say $sql;
    my $tb        = $self->dbh->selectall_hashref($sql, 'ecdcNoticeId');
    my $toEntry   = $pageNumber * 50;
    my $fromEntry = $toEntry - 49;
    # say "from : $fromEntry -> to : $toEntry";
    my $totalEcdcNotices = 0;
    for my $ecdcNoticeId (sort{$a <=> $b} keys %$tb) {
        next unless keys %{$drugsNotices{$ecdcNoticeId}}; # Happens when we are indexing notices live only.
        my ($hasSearchedDrug, $hasSearchedOutcome, $hasSearchedReaction) = (0, 0);
        if ($ecdcDrug) {
            for my $ecdcDrugId (sort{$a <=> $b} keys %{$drugsNotices{$ecdcNoticeId}}) {
                $hasSearchedDrug = 1 if $ecdcDrug eq $ecdcDrugId;
            }
            next unless $hasSearchedDrug;
        }
        if ($covidVaccinesOnly eq 'true') {
            my $hasCovidVaccine = 0;
            for my $ecdcDrugId (sort{$a <=> $b} keys %{$drugsNotices{$ecdcNoticeId}}) {
                my $ecdcDrugName = $drugs{$ecdcDrugId}->{'name'} // die;
                $hasCovidVaccine = 1 if $ecdcDrugName =~ /COVID/;
            }
            next unless $hasCovidVaccine;
        }
        if ($ecdcReactionOutcome || $ecdcReaction) {
            for my $ecdcReactionId (sort{$a <=> $b} keys %{$noticeReactions{$ecdcNoticeId}}) {
                my $ecdcReactionOutcomeId = $noticeReactions{$ecdcNoticeId}->{$ecdcReactionId}->{'ecdcReactionOutcomeId'} // die;
                if ($ecdcReactionOutcome) {
                    $hasSearchedOutcome = 1 if $ecdcReactionOutcomeId eq $ecdcReactionOutcome;
                }
                if ($ecdcReaction) {
                    $hasSearchedReaction = 1 if $ecdcReactionId eq $ecdcReaction;
                }
            }
            if ($ecdcReactionOutcome) {
                next unless $hasSearchedOutcome;
            }
            if ($ecdcReaction) {
                next unless $hasSearchedReaction;
            }
        }
        $totalEcdcNotices++;
        if ($totalEcdcNotices >= $fromEntry && $totalEcdcNotices <= $toEntry) {
            my $name                         = %$tb{$ecdcNoticeId}->{'name'}                               // die;
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
            $obj{'name'}                         = $name;
            $obj{'ecdcYearName'}                 = $ecdcYearName;
            $obj{'receiptDate'}                  = $receiptDate;
            $obj{'ecdcSexName'}                  = $ecdcSexName;
            $obj{'ecdcAgeGroupName'}             = $ecdcAgeGroupName;
            $obj{'ecdcSeriousnessName'}          = $ecdcSeriousnessName;
            $obj{'ecdcReporterTypeName'}         = $ecdcReporterTypeName;
            $obj{'ecdcGeographicalOriginName'}   = $ecdcGeographicalOriginName;
            $obj{'url'}                          = $url;

            # Incrementing related substances.
            for my $ecdcDrugId (sort{$a <=> $b} keys %{$drugsNotices{$ecdcNoticeId}}) {
                my $ecdcDrugName = $drugs{$ecdcDrugId}->{'name'} // die;
                my %dObj = ();
                $dObj{'name'} = $ecdcDrugName;
                push @{$obj{'substances'}}, \%dObj;
            }

            # Incrementing related reactions.
            for my $ecdcReactionId (sort{$a <=> $b} keys %{$noticeReactions{$ecdcNoticeId}}) {
                my $ecdcReactionOutcomeId = $noticeReactions{$ecdcNoticeId}->{$ecdcReactionId}->{'ecdcReactionOutcomeId'} // die;
                my $ecdcReactionName = $reactions{$ecdcReactionId}->{'name'} // die;
                my $ecdcReactionOutcomeName = $reactionsOutcomes{$ecdcReactionOutcomeId}->{'name'} // die;
                my %rObj = ();
                $rObj{'name'} = $ecdcReactionName;
                $rObj{'outcome'} = $ecdcReactionOutcomeName;
                push @{$obj{'reactions'}}, \%rObj;
            }
            push @ecdcNotices, \%obj;
        }
    }
    my ($maxPages, %pages) = data_formatting::paginate($pageNumber, $totalEcdcNotices, 50);
    # p%pages;

    $self->render(
        pageNumber       => $pageNumber,
        maxPages         => $maxPages,
        totalEcdcNotices => $totalEcdcNotices,
        noticeSearch     => $noticeSearch,
        ecdcNotices      => \@ecdcNotices,
        pages            => \%pages
    );
}

1;