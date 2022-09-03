package OpenVaet::Controller::LethalityRatioUsa;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Log;
use JSON;
use Data::Printer;
use FindBin;
use lib "$FindBin::Bin/../lib";
use session;

sub lethality_ratio_usa {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // 'fr';

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    my $statistics;
    open my $in, '<:utf8', 'stats/ratios_reports_by_dates.json';
    while (<$in>) {
        $statistics .= $_;
    }
    close $in;
    $statistics = decode_json($statistics);
    my %statistics = %$statistics;

    $self->render(
        currentLanguage => $currentLanguage,
        languages => \%languages,
        statistics => \%statistics
    );
}

1;