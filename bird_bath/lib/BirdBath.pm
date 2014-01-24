package BirdBath;
use Mojo::Base 'Mojolicious';
use Mango;

sub startup {
  my $self = shift;

  my $config = $self->plugin('Config');
  $self->config($config);

  $self->helper(mango => sub {
  	state $mango = Mango->new;
  	return $mango;
  });

  $self->helper(tweets => sub {
  	my $self = shift;
  	return $self->mango->db('birdbath')->collection('tweets');
  });

  $self->helper(accounts => sub {
  	my $self = shift;
  	return $self->mango->db('birdbath')->collection('accounts');
  });

  $self->helper(users => sub {
  	my $self = shift;
  	return $self->mango->db('birdbath')->collection('users');
  });

  my $r = $self->routes;
  $r->get('/')->to('home#welcome');
  $r->get('/logout')->to('home#logout');
  $r->get('/github')->to('github#github');
  $r->get('/twitter')->to('twitter#twitter');
  $r->get('/twitter/callback')->to('twitter#callback');

  my $auth = $r->bridge->to(cb => sub {
  	my $self = shift;
  	return 0 unless $self->session->{user};
  	return 1;
  });
  $auth->get('/tweets')->to('home#tweets');
  $auth->post('/tweets')->to('home#tweet');
  $auth->get('/accounts')->to('home#accounts');
  $auth->post('/approve')->to('home#approve');
  $auth->post('/reject')->to('home#reject');
  $auth->post('/undo')->to('home#undo');
  $auth->post('/update')->to('home#update');
}

1;
