package BirdBath;
use Mojo::Base 'Mojolicious';
use Mango;

sub startup {
  my $self = shift;

  $self->helper(mango => sub {
  	state $mango = Mango->new;
  	return $mango;
  });

  $self->helper(tweets => sub {
  	return shift->mango->db('birdbath')->collection('tweets');
  });

  $self->helper(users => sub {
  	return shift->mango->db('birdbath')->collection('users');
  });

  my $r = $self->routes;
  $r->get('/')->to('example#welcome');
}

1;
