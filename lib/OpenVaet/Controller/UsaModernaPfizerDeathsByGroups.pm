package OpenVaet::Controller::UsaModernaPfizerDeathsByGroups;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Log;
use JSON;
use Data::Printer;
use Math::Round qw(nearest);
use FindBin;
use lib "$FindBin::Bin/../lib";
use session;

sub usa_moderna_pfizer_deaths_by_groups {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // 'fr';

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    my $statistics;
    open my $in, '<:utf8', 'stats/covid_deaths_by_ages.json';
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