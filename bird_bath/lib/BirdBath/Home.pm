package BirdBath::Home;

use Mojo::Base 'Mojolicious::Controller';

sub welcome {
  my $self = shift;

  $self->render(msg => 'Welcome to the Mojolicious real-time web framework!');
}

1;
