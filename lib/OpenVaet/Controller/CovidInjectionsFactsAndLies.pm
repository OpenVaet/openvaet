package OpenVaet::Controller::CovidInjectionsFactsAndLies;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Log;
use JSON;
use Data::Printer;
use Email::Valid;
use FindBin;
use lib "$FindBin::Bin/../lib";
use session;

sub covid_injections_facts_and_lies {
    my $self = shift;
    my $currentLanguage = $self->param('currentLanguage') // 'en';

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    $self->render(
        currentLanguage => $currentLanguage,
        languages => \%languages
    );
}

sub traditional_vaccines_controversies {
    my $self = shift;
    my $currentLanguage = $self->param('currentLanguage') // 'en';

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    $self->render(
        currentLanguage => $currentLanguage,
        languages => \%languages
    );
}

1;