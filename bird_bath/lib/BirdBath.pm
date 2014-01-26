package BirdBath;
use Mojo::Base 'Mojolicious';

sub startup {
  my $self = shift;

  my $config = $self->plugin('Config');
  $self->config($config);

  $self->plugin('BirdBath::Plugin::OAuth2');
  $self->plugin('BirdBath::Plugin::Mango');
  $self->plugin('BirdBath::Plugin::Routes');

  my $r = $self->routes->find('root');
  $r->get('/')->to('home#welcome');
  $r->get('/logout')->to('home#logout');
  $r->get('/twitter')->to('twitter#twitter');
  $r->get('/twitter/callback')->to('twitter#callback'); 

  # View only or any auth user
  my $auth = $self->routes->find('auth');
  $auth->get('/manage')->to('manage#welcome');
  $auth->get('/tweets')->to('home#tweets');
  $auth->get('/accounts')->to('home#accounts');
  $auth->post('/request')->to('manage#request');
  $auth->post('/search')->to('search#search');
  $auth->post('/timeline')->to('search#timeline');
  $auth->post('/account-remove')->to('manage#remove_account');

  # Contributor only
  my $contributor = $self->routes->find('contributor');
  $contributor->post('/tweets')->to('home#tweet');
  $contributor->post('/retweet')->to('home#retweet');

  # Editor only
  my $editor = $self->routes->find('editor');
  $editor->post('/approve')->to('home#approve');
  $editor->post('/reject')->to('home#reject');
  $editor->post('/undo')->to('home#undo');
  $editor->post('/update')->to('home#update');

  # Admin only
  my $admin = $self->routes->find('admin');
  $admin->post('/user-approve')->to('manage#accept_user');
  $admin->post('/user-reject')->to('manage#reject_user');
  $admin->post('/user-save')->to('manage#save_user');  
  $admin->post('/user-remove')->to('manage#remove_user');
}

1;
