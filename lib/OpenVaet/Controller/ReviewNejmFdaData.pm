package OpenVaet::Controller::ReviewNejmFdaData;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Log;
use JSON;
use Data::Printer;
use FindBin;
use lib "$FindBin::Bin/../lib";
use session;
use time;

sub calc_days_difference {
    my ($date1, $date2) = @_;
    die unless $date1 && $date2;
    my $date1Ftd = datetime_from_compdate($date1);
    my $date2Ftd = datetime_from_compdate($date2);
    # say "date1Ftd : $date1Ftd";
    # say "date2Ftd : $date2Ftd";
    my $daysDifference = time::calculate_days_difference($date1Ftd, $date2Ftd);
    return $daysDifference;
}

sub date_from_compdate {
    my ($date) = shift;
    my ($y, $m, $d) = $date =~ /(....)(..)(..)/;
    die unless $y && $m && $d;
    return "$y-$m-$d";
}

sub datetime_from_compdate {
    my ($date) = shift;
    my ($y, $m, $d) = $date =~ /(....)(..)(..)/;
    die unless $y && $m && $d;
    return "$y-$m-$d 12:00:00";
}

sub json_from_file {
    my $file = shift;
    if (-f $file) {
        my $json;
        eval {
            open my $in, '<:utf8', $file;
            while (<$in>) {
                $json .= $_;
            }
            close $in;
            $json = decode_json($json) or die $!;
        };
        if ($@) {
            {
                local $/;
                open (my $fh, $file) or die $!;
                $json = <$fh>;
                close $fh;
            }
            eval {
                $json = decode_json($json);
            };
            if ($@) {
                die "failed parsing json : " . @!;
            }
        }
        return %$json;
    } else {
        return {};
    }
}

sub review_nejm_fda_data {
    my $self = shift;
    my $currentLanguage = $self->param('currentLanguage') // 'fr';

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    my $firstDoseDataFile = 'public/doc/pfizer_trials/first_doses_stats.json';
    my %firstDoseData = json_from_file($firstDoseDataFile);
    my $secondDoseDataFile = 'public/doc/pfizer_trials/second_doses_stats.json';
    my %secondDoseData = json_from_file($secondDoseDataFile);
    my $casesDataFile = 'public/doc/pfizer_trials/efficacy_cases_stats.json';
    my %casesData = json_from_file($casesDataFile);
    # p%secondDoseData;

    my %dose1Sites = ();
    for my $trialSiteId (sort{$a <=> $b} keys %firstDoseData) {
        my $trialSiteName = $firstDoseData{$trialSiteId}->{'trialSiteName'} // die;
        my $trialSitePostalCode = $firstDoseData{$trialSiteId}->{'trialSitePostalCode'};
        my $totalSubjects = $firstDoseData{$trialSiteId}->{'totalSubjects'} // die;
        $dose1Sites{$totalSubjects}->{$trialSiteId}->{'trialSiteName'} = $trialSiteName;
        $dose1Sites{$totalSubjects}->{$trialSiteId}->{'trialSitePostalCode'} = $trialSitePostalCode;
    }
    my %dose2Sites = ();
    for my $trialSiteId (sort{$a <=> $b} keys %secondDoseData) {
        my $trialSiteName = $secondDoseData{$trialSiteId}->{'trialSiteName'} // die "trialSiteId : $trialSiteId";
        my $trialSitePostalCode = $secondDoseData{$trialSiteId}->{'trialSitePostalCode'};
        my $totalSubjects = $secondDoseData{$trialSiteId}->{'totalSubjects'} // die;
        $dose2Sites{$totalSubjects}->{$trialSiteId}->{'trialSiteName'} = $trialSiteName;
        $dose2Sites{$totalSubjects}->{$trialSiteId}->{'trialSitePostalCode'} = $trialSitePostalCode;
    }
    my %casesSites = ();
    for my $trialSiteId (sort{$a <=> $b} keys %casesData) {
        my $trialSiteName = $casesData{$trialSiteId}->{'trialSiteName'} // die "trialSiteId : $trialSiteId";
        my $trialSitePostalCode = $casesData{$trialSiteId}->{'trialSitePostalCode'};
        my $totalSubjects = $casesData{$trialSiteId}->{'totalSubjects'} // die;
        $casesSites{$totalSubjects}->{$trialSiteId}->{'trialSiteName'} = $trialSiteName;
        $casesSites{$totalSubjects}->{$trialSiteId}->{'trialSitePostalCode'} = $trialSitePostalCode;
    }

    $self->render(
        currentLanguage => $currentLanguage,
        languages => \%languages,
        dose1Sites => \%dose1Sites,
        dose2Sites => \%dose2Sites,
        casesSites => \%casesSites
    );
}

sub load_dose_1_week_by_week {
    my $self = shift;

    my $siteTarget      = $self->param('siteTarget')      // die;
    my $currentLanguage = $self->param('currentLanguage') // die;
    my $mainWidth       = $self->param('mainWidth')       // die;
    my $mainHeight      = $self->param('mainHeight')      // die;
    say "siteTarget : $siteTarget";

    my $firstDoseDataFile = 'public/doc/pfizer_trials/first_doses_stats.json';
    my %firstDoseData = json_from_file($firstDoseDataFile);

    my %weekByWeekFirstDose = ();
    my ($totalBnt, $totalPlacebo, $totalSubjects, $fromDate, $toDate, $daysDifference) = (0, 0, 0);
    $fromDate = $firstDoseData{$siteTarget}->{'firstDose1'} // die;
    $toDate = $firstDoseData{$siteTarget}->{'lastDose1'} // die;
    $daysDifference = calc_days_difference($fromDate, $toDate);
    $fromDate = date_from_compdate($fromDate);
    $toDate = date_from_compdate($toDate);
    for my $weekNumber (sort{$a <=> $b} keys %{$firstDoseData{$siteTarget}->{'weekNumbers'}}) {
        my $bNT162b2 = $firstDoseData{$siteTarget}->{'weekNumbers'}->{$weekNumber}->{'BNT162b2'} // 0;
        my $placebo = $firstDoseData{$siteTarget}->{'weekNumbers'}->{$weekNumber}->{'Placebo'} // 0;
        $weekByWeekFirstDose{$weekNumber}->{'bNT162b2'} = $bNT162b2;
        $weekByWeekFirstDose{$weekNumber}->{'placebo'} = $placebo;
        $totalSubjects += $bNT162b2;
        $totalSubjects += $placebo;
        $totalBnt += $bNT162b2;
        $totalPlacebo += $placebo;
    }
    # p%weekByWeekFirstDose;

    $self->render(
        currentLanguage     => $currentLanguage,
        totalBnt            => $totalBnt,
        totalPlacebo        => $totalPlacebo,
        totalSubjects       => $totalSubjects,
        fromDate            => $fromDate,
        toDate              => $toDate,
        daysDifference      => $daysDifference,
        mainWidth           => $mainWidth,
        mainHeight          => $mainHeight,
        weekByWeekFirstDose => \%weekByWeekFirstDose
    );
}

sub load_dose_1_demographic {
    my $self = shift;

    my $siteTarget      = $self->param('siteTarget')      // die;
    my $currentLanguage = $self->param('currentLanguage') // die;
    my $mainWidth       = $self->param('mainWidth')       // die;
    my $mainHeight      = $self->param('mainHeight')      // die;
    say "siteTarget : $siteTarget";

    my $firstDoseDataFile = 'public/doc/pfizer_trials/first_doses_stats.json';
    my %firstDoseData = json_from_file($firstDoseDataFile);

    die unless exists $firstDoseData{$siteTarget};
    my %demographics = %{$firstDoseData{$siteTarget}};

    $self->render(
        currentLanguage     => $currentLanguage,
        mainWidth           => $mainWidth,
        mainHeight          => $mainHeight,
        demographics => \%demographics
    );
}

sub load_dose_1_mapping {
    my $self = shift;

    my $siteTarget      = $self->param('siteTarget')      // die;
    my $currentLanguage = $self->param('currentLanguage') // die;
    my $mainWidth       = $self->param('mainWidth')       // die;
    my $mainHeight      = $self->param('mainHeight')      // die;

    say "siteTarget : $siteTarget";
    say "mainWidth  : $mainWidth";
    say "mainHeight : $mainHeight";

    my $firstDoseDataFile = 'public/doc/pfizer_trials/first_doses_stats.json';
    my %firstDoseData = json_from_file($firstDoseDataFile);
    my %sites = ();
    for my $trialSiteId (sort{$a <=> $b} keys %firstDoseData) {
        next if $trialSiteId == 0;
        if ($siteTarget) {
            next unless $trialSiteId eq $siteTarget;
        }
        my $trialSiteName = $firstDoseData{$trialSiteId}->{'trialSiteName'} // die;
        my $trialSitePostalCode = $firstDoseData{$trialSiteId}->{'trialSitePostalCode'} // die;
        my $totalSubjects = $firstDoseData{$trialSiteId}->{'totalSubjects'} // die;
        my $trialSiteLatitude = $firstDoseData{$trialSiteId}->{'trialSiteLatitude'} // die;
        my $trialSiteLongitude = $firstDoseData{$trialSiteId}->{'trialSiteLongitude'} // die;
        my $trialSiteInvestigator = $firstDoseData{$trialSiteId}->{'trialSiteInvestigator'} // die;
        my $trialSiteAddress = $firstDoseData{$trialSiteId}->{'trialSiteAddress'} // die;
        my $trialSiteCity = $firstDoseData{$trialSiteId}->{'trialSiteCity'} // die;
        $sites{$trialSiteId}->{'trialSiteName'}   = $trialSiteName;
        $sites{$trialSiteId}->{'totalSubjects'} = $totalSubjects;
        $sites{$trialSiteId}->{'trialSiteId'} = $trialSiteId;
        $sites{$trialSiteId}->{'trialSiteAddress'} = $trialSiteAddress;
        $sites{$trialSiteId}->{'trialSitePostalCode'} = $trialSitePostalCode;
        $sites{$trialSiteId}->{'trialSiteCity'} = $trialSiteCity;
        $sites{$trialSiteId}->{'trialSiteInvestigator'} = $trialSiteInvestigator;
        $sites{$trialSiteId}->{'trialSiteLatitude'} = $trialSiteLatitude;
        $sites{$trialSiteId}->{'trialSiteLongitude'} = $trialSiteLongitude;
    }

    $self->render(
        currentLanguage => $currentLanguage,
        mainWidth       => $mainWidth,
        mainHeight      => $mainHeight,
        sites           => \%sites
    );
}

sub load_dose_2_week_by_week {
    my $self = shift;

    my $siteTarget      = $self->param('siteTarget')      // die;
    my $currentLanguage = $self->param('currentLanguage') // die;
    my $mainWidth       = $self->param('mainWidth')       // die;
    my $mainHeight      = $self->param('mainHeight')      // die;
    say "siteTarget : $siteTarget";

    my $secondDoseDataFile = 'public/doc/pfizer_trials/second_doses_stats.json';
    my %secondDoseData = json_from_file($secondDoseDataFile);

    my %weekByWeekSecondDose = ();
    my ($totalBnt, $totalPlacebo, $totalSubjects, $fromDate, $toDate, $daysDifference) = (0, 0, 0);
    $fromDate = $secondDoseData{$siteTarget}->{'firstDose2'} // die;
    $toDate = $secondDoseData{$siteTarget}->{'lastDose2'} // die;
    $daysDifference = calc_days_difference($fromDate, $toDate);
    $fromDate = date_from_compdate($fromDate);
    $toDate = date_from_compdate($toDate);
    for my $weekNumber (sort{$a <=> $b} keys %{$secondDoseData{$siteTarget}->{'weekNumbers'}}) {
        my $bNT162b2 = $secondDoseData{$siteTarget}->{'weekNumbers'}->{$weekNumber}->{'BNT162b2'} // 0;
        my $placebo = $secondDoseData{$siteTarget}->{'weekNumbers'}->{$weekNumber}->{'Placebo'} // 0;
        $weekByWeekSecondDose{$weekNumber}->{'bNT162b2'} = $bNT162b2;
        $weekByWeekSecondDose{$weekNumber}->{'placebo'} = $placebo;
        $totalSubjects += $bNT162b2;
        $totalSubjects += $placebo;
        $totalBnt += $bNT162b2;
        $totalPlacebo += $placebo;
    }

    $self->render(
        currentLanguage     => $currentLanguage,
        totalBnt            => $totalBnt,
        totalPlacebo        => $totalPlacebo,
        totalSubjects       => $totalSubjects,
        fromDate            => $fromDate,
        toDate              => $toDate,
        daysDifference      => $daysDifference,
        mainWidth           => $mainWidth,
        mainHeight          => $mainHeight,
        weekByWeekSecondDose => \%weekByWeekSecondDose
    );
}

sub load_dose_2_demographic {
    my $self = shift;

    my $siteTarget      = $self->param('siteTarget')      // die;
    my $currentLanguage = $self->param('currentLanguage') // die;
    my $mainWidth       = $self->param('mainWidth')       // die;
    my $mainHeight      = $self->param('mainHeight')      // die;
    say "siteTarget : $siteTarget";

    my $secondDoseDataFile = 'public/doc/pfizer_trials/second_doses_stats.json';
    my %secondDoseData = json_from_file($secondDoseDataFile);

    die unless exists $secondDoseData{$siteTarget};
    my %demographics = %{$secondDoseData{$siteTarget}};
    # p%demographics;

    $self->render(
        currentLanguage     => $currentLanguage,
        mainWidth           => $mainWidth,
        mainHeight          => $mainHeight,
        demographics => \%demographics
    );
}

sub load_dose_2_mapping {
    my $self = shift;

    my $siteTarget      = $self->param('siteTarget')      // die;
    my $currentLanguage = $self->param('currentLanguage') // die;
    my $mainWidth       = $self->param('mainWidth')       // die;
    my $mainHeight      = $self->param('mainHeight')      // die;

    say "siteTarget : $siteTarget";
    say "mainWidth  : $mainWidth";
    say "mainHeight : $mainHeight";

    my $secondDoseDataFile = 'public/doc/pfizer_trials/second_doses_stats.json';
    my %secondDoseData = json_from_file($secondDoseDataFile);
    my %sites = ();
    for my $trialSiteId (sort{$a <=> $b} keys %secondDoseData) {
        next if $trialSiteId == 0;
        if ($siteTarget) {
            next unless $trialSiteId eq $siteTarget;
        }
        my $trialSiteName = $secondDoseData{$trialSiteId}->{'trialSiteName'} // die;
        my $trialSitePostalCode = $secondDoseData{$trialSiteId}->{'trialSitePostalCode'} // die;
        my $totalSubjects = $secondDoseData{$trialSiteId}->{'totalSubjects'} // die;
        my $trialSiteLatitude = $secondDoseData{$trialSiteId}->{'trialSiteLatitude'} // die;
        my $trialSiteLongitude = $secondDoseData{$trialSiteId}->{'trialSiteLongitude'} // die;
        my $trialSiteInvestigator = $secondDoseData{$trialSiteId}->{'trialSiteInvestigator'} // die;
        my $trialSiteAddress = $secondDoseData{$trialSiteId}->{'trialSiteAddress'} // die;
        my $trialSiteCity = $secondDoseData{$trialSiteId}->{'trialSiteCity'} // die;
        my $totalCases = $secondDoseData{$trialSiteId}->{'totalCases'} // 0;
        $sites{$trialSiteId}->{'totalCases'}   = $totalCases;
        $sites{$trialSiteId}->{'trialSiteName'}   = $trialSiteName;
        $sites{$trialSiteId}->{'totalSubjects'} = $totalSubjects;
        $sites{$trialSiteId}->{'trialSiteId'} = $trialSiteId;
        $sites{$trialSiteId}->{'trialSiteAddress'} = $trialSiteAddress;
        $sites{$trialSiteId}->{'trialSitePostalCode'} = $trialSitePostalCode;
        $sites{$trialSiteId}->{'trialSiteCity'} = $trialSiteCity;
        $sites{$trialSiteId}->{'trialSiteInvestigator'} = $trialSiteInvestigator;
        $sites{$trialSiteId}->{'trialSiteLatitude'} = $trialSiteLatitude;
        $sites{$trialSiteId}->{'trialSiteLongitude'} = $trialSiteLongitude;
    }

    $self->render(
        currentLanguage => $currentLanguage,
        mainWidth       => $mainWidth,
        mainHeight      => $mainHeight,
        sites           => \%sites
    );
}

sub load_efficacy_cases {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // die;
    my $mainWidth       = $self->param('mainWidth')       // die;
    my $mainHeight      = $self->param('mainHeight')      // die;

    say "mainWidth  : $mainWidth";
    say "mainHeight : $mainHeight";

    my $efficacySubjectsFile = 'public/doc/pfizer_trials/efficacy_subjects.json';
    my %efficacySubjects = json_from_file($efficacySubjectsFile);
    for my $swabDate (sort{$a <=> $b} keys %efficacySubjects) {
        for my $subjectId (sort{$a <=> $b} keys %{$efficacySubjects{$swabDate}}) {
            # p$efficacySubjects{$swabDate}->{$subjectId};
            my $dose1Date = $efficacySubjects{$swabDate}->{$subjectId}->{'dose1Date'} // die;
            $dose1Date    = date_from_compdate($dose1Date);
            my $dose2Date = $efficacySubjects{$swabDate}->{$subjectId}->{'dose2Date'} // die;
            $dose2Date    = date_from_compdate($dose2Date);
            my $randomizationDate = $efficacySubjects{$swabDate}->{$subjectId}->{'randomizationDate'} // die;
            $randomizationDate = date_from_compdate($randomizationDate);
            my $screeningDate = $efficacySubjects{$swabDate}->{$subjectId}->{'screeningDate'} // die;
            $screeningDate = date_from_compdate($screeningDate);
            my $swabDate = $efficacySubjects{$swabDate}->{$subjectId}->{'swabDate'} // die;
            my $swabDateFormat = date_from_compdate($swabDate);
            $efficacySubjects{$swabDate}->{$subjectId}->{'dose1Date'} = $dose1Date;
            $efficacySubjects{$swabDate}->{$subjectId}->{'dose2Date'} = $dose2Date;
            $efficacySubjects{$swabDate}->{$subjectId}->{'randomizationDate'} = $randomizationDate;
            $efficacySubjects{$swabDate}->{$subjectId}->{'screeningDate'} = $screeningDate;
            $efficacySubjects{$swabDate}->{$subjectId}->{'swabDate'} = $swabDateFormat;
        }
    }

    $self->render(
        currentLanguage  => $currentLanguage,
        mainWidth        => $mainWidth,
        mainHeight       => $mainHeight,
        efficacySubjects => \%efficacySubjects
    );
}

sub load_efficacy_by_sites_countries {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // die;
    my $showUSAStates   = $self->param('showUSAStates')   // die;
    my $mainWidth       = $self->param('mainWidth')       // die;
    my $mainHeight      = $self->param('mainHeight')      // die;

    say "mainWidth     : $mainWidth";
    say "showUSAStates : $showUSAStates";
    say "mainHeight    : $mainHeight";

    my $efficacyStatsFile = 'public/doc/pfizer_trials/efficacy_stats.json';
    my %efficacyStats = json_from_file($efficacyStatsFile);

    $self->render(
        showUSAStates   => $showUSAStates,
        currentLanguage => $currentLanguage,
        mainWidth       => $mainWidth,
        mainHeight      => $mainHeight,
        efficacyStats   => \%efficacyStats
    );
}

sub load_efficacy_by_sites {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // die;
    my $mainWidth       = $self->param('mainWidth')       // die;
    my $mainHeight      = $self->param('mainHeight')      // die;

    say "mainWidth  : $mainWidth";
    say "mainHeight : $mainHeight";

    my $efficacyStatsFile = 'public/doc/pfizer_trials/efficacy_sites_stats.json';
    my %efficacyStats = json_from_file($efficacyStatsFile);

    $self->render(
        currentLanguage => $currentLanguage,
        mainWidth       => $mainWidth,
        mainHeight      => $mainHeight,
        efficacyStats   => \%efficacyStats
    );
}

sub load_efficacy_cases_week_by_week {
    my $self = shift;

    my $siteTarget      = $self->param('siteTarget')      // die;
    my $currentLanguage = $self->param('currentLanguage') // die;
    my $mainWidth       = $self->param('mainWidth')       // die;
    my $mainHeight      = $self->param('mainHeight')      // die;
    say "siteTarget : $siteTarget";

    my $casesDataFile = 'public/doc/pfizer_trials/efficacy_cases_stats.json';
    my %casesData = json_from_file($casesDataFile);

    my %weekByWeekCases = ();
    my ($totalBnt, $totalPlacebo, $totalSubjects, $fromDate, $toDate, $daysDifference) = (0, 0, 0);
    $fromDate = $casesData{$siteTarget}->{'firstCase'} // die;
    $toDate = $casesData{$siteTarget}->{'lastCase'} // die;
    $daysDifference = calc_days_difference($fromDate, $toDate);
    $fromDate = date_from_compdate($fromDate);
    $toDate = date_from_compdate($toDate);
    for my $weekNumber (sort{$a <=> $b} keys %{$casesData{$siteTarget}->{'weekNumbers'}}) {
        my $bNT162b2 = $casesData{$siteTarget}->{'weekNumbers'}->{$weekNumber}->{'BNT162b2'} // 0;
        my $placebo = $casesData{$siteTarget}->{'weekNumbers'}->{$weekNumber}->{'Placebo'} // 0;
        $weekByWeekCases{$weekNumber}->{'bNT162b2'} = $bNT162b2;
        $weekByWeekCases{$weekNumber}->{'placebo'} = $placebo;
        $totalSubjects += $bNT162b2;
        $totalSubjects += $placebo;
        $totalBnt += $bNT162b2;
        $totalPlacebo += $placebo;
    }
    # p%weekByWeekCases;

    $self->render(
        currentLanguage     => $currentLanguage,
        totalBnt            => $totalBnt,
        totalPlacebo        => $totalPlacebo,
        totalSubjects       => $totalSubjects,
        fromDate            => $fromDate,
        toDate              => $toDate,
        daysDifference      => $daysDifference,
        mainWidth           => $mainWidth,
        mainHeight          => $mainHeight,
        weekByWeekCases => \%weekByWeekCases
    );
}

1;