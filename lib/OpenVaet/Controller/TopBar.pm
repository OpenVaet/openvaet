package OpenVaet::Controller::TopBar;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Log;
use JSON;
use Data::Printer;
use FindBin;
use lib "$FindBin::Bin/../lib";
use session;

sub top_bar {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // die;
    my $mainWidth       = $self->param('mainWidth')       // die;
    my $mainHeight      = $self->param('mainHeight')      // die;

    say "mainWidth  : $mainWidth";
    say "mainHeight : $mainHeight";

    my %languages       = ();
    $languages{'fr'}    = 'French';
    $languages{'en'}    = 'English';

    $self->render(
        currentLanguage => $currentLanguage,
        mainWidth       => $mainWidth,
        mainHeight      => $mainHeight,
        languages       => \%languages
    );
}

1;