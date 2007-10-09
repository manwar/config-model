# $Author: ddumont $
# $Date: 2007-10-09 11:15:06 $
# $Name: not supported by cvs2svn $
# $Revision: 1.14 $

#    Copyright (c) 2005-2007 Dominique Dumont.
#
#    This file is part of Config-Model.
#
#    Config-Model is free software; you can redistribute it and/or
#    modify it under the terms of the GNU Lesser Public License as
#    published by the Free Software Foundation; either version 2.1 of
#    the License, or (at your option) any later version.
#
#    Config-Model is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#    Lesser Public License for more details.
#
#    You should have received a copy of the GNU Lesser Public License
#    along with Config-Model; if not, write to the Free Software
#    Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA

package Config::Model::HashId ;
use Config::Model::Exception ;
use Scalar::Util qw(weaken) ;
use warnings ;
use Carp;
use strict;

use base qw/Config::Model::AnyId/ ;

use vars qw($VERSION) ;
$VERSION = sprintf "%d.%03d", q$Revision: 1.14 $ =~ /(\d+)\.(\d+)/;

=head1 NAME

Config::Model::HashId - Handle hash element for configuration model

=head1 SYNOPSIS

 $model ->create_config_class 
  (
   ...
   element 
   => [ 
       bounded_hash 
       => { type => 'hash',
            index_type  => 'integer',
            min => 1, 
            max => 123, 
            max_nb => 2 ,
            cargo_type => 'leaf',
            cargo_args => {value_type => 'string'},
          },
      ]
  ) ;

=head1 DESCRIPTION

This class provides hash elements for a L<Config::Model::Node>.

The hash index can either be en enumerated type, a boolean, an integer
or a string.

=cut

=head1 CONSTRUCTOR

HashId object should not be created directly.

=cut

sub new {
    my $type = shift;
    my %args = @_ ;

    my $self = $type->SUPER::new(\%args) ;

    $self->{data} = {} ;
    $self->{list} = [] ;

    Config::Model::Exception::Model->throw 
        (
         object => $self,
         error => "Undefined index_type"
        ) unless defined $args{index_type} ;

    $self->handle_args(%args) ;

    return $self;
}

=head1 Hash model declaration

See
L<model declaration section|Config::Model::AnyId/"Hash or list model declaration">
from L<Config::Model::AnyId>.

=cut

sub set {
    my $self = shift ;

    $self->SUPER::set(@_) ;

    my $idx_type = $self->{index_type} ;

    # remove unwanted items
    my $data = $self->{data} ;

    my $idx = 1 ;
    my $wrong = sub {
        my $k = shift ;
        if ($idx_type eq 'integer') {
            return 1 if defined $self->{max} and $k > $self->{max} ;
            return 1 if defined $self->{min} and $k < $self->{min} ;
	}
        return 1 if defined $self->{max_nb} and $idx++ > $self->{max_nb};
        return 0 ;
    } ;

    # delete entries that no longer fit the constraints imposed by the
    # warp mechanism
    foreach my $k (sort keys %$data) {
	next unless $wrong->($k) ;
	print "set: ",$self->name," deleting id $k\n" if $::debug ;
	delete $data->{$k}  ;
    }
}

=head1 Methods

=head2 get_type

Returns C<hash>.

=cut

sub get_type {
    my $self = shift;
    return 'hash' ;
}

=head2 fetch_size

Returns the nb of elements of the hash.

=cut

sub fetch_size {
    my $self = shift;
    return scalar keys %{$self->{data}} ;
}

sub _get_all_indexes {
    my $self = shift;
    return $self->{ordered} ? @{$self->{list}}
         :                    sort keys %{$self->{data}} ;
}

# fetch without any check 
sub _fetch_with_id {
    my ($self,$key) = @_ ;
    return $self->{data}{$key};
}

# store without any check
sub _store {
    my ($self, $key, $value) =  @_ ;
    push @{$self->{list}}, $key 
      unless exists $self->{data}{$key};
    return $self->{data}{$key} = $value ;
}

sub _exists {
    my ($self,$key) = @_ ;
    return exists $self->{data}{$key};
}

sub _defined {
    my ($self,$key) = @_ ;
    return defined $self->{data}{$key};
}

#internal
sub auto_create_elements {
    my $self = shift ;

    my $auto_p = $self->{auto_create} ;
    # create empty slots
    map {
	$self->_store($_, undef) unless exists $self->{data}{$_};
    }  (ref $auto_p ? @$auto_p : ($auto_p)) ;
}

# internal
sub create_default {
    my $self = shift ;
    my @temp = keys %{$self->{data}} ;

    return if @temp ;

    # hash is empty so create empty element for default keys
    my $def = $self->get_default_keys ;
    map {$self->_store($_,undef) } @$def ;

    if (defined $self->{default_with_init}) {
	my $h = $self->{default_with_init} ;
	foreach my $def_key (keys %$h) {
	    $self->fetch_with_id($def_key)->load($h->{$def_key}) ;
	}
    }
}

sub _delete {
    my ($self,$key) = @_ ;

    # remove key in ordered list
    @{$self->{list}} = grep { $_ ne $key } @{ $self->{list}} ;

    return delete $self->{data}{$key};
}

sub _clear {
    my ($self) = @_ ;
    $self->{list} = [];
    $self->{data} = {};
}

=head2 firstkey

Returns the first key of the hash. Behaves like C<each> core perl
function.

=cut

# hash only method
sub firstkey {
    my $self = shift ;

    $self->warp 
      if ($self->{warp} and @{$self->{warp_info}{computed_master}});

    $self->create_default if defined $self->{default};

    # reset "each" iterator (to be sure, map is also an iterator)
    my @list = $self->_get_all_indexes ;
    $self->{each_list} = \@list ;
    return shift @list ;
}

=head2 nextkey

Returns the next key of the hash. Behaves like C<each> core perl
function.

=cut

# hash only method
sub nextkey {
    my $self = shift ;

    $self->warp 
      if ($self->{warp} and @{$self->{warp_info}{computed_master}});

    my $res =  shift @{$self->{each_list}} ;

    return $res if defined $res ;

    # reset list for next call to next_keys
    $self->{each_list} = [ $self->_get_all_indexes  ] ;

    return undef ;
}

=head2 swap ( key1 , key2 )

Swap the order of the 2 keys. Ignored for non ordered hash.

=cut

sub swap {
    my $self = shift ;
    my ($key1,$key2) = @_ ;


    foreach my $k (@_) {
	Config::Model::Exception::User
	    -> throw (
		      object => $self,
		      message => "swap: unknow key $k"
		     )
	      unless exists $self->{data}{$k} ;
    }

    my $list = $self->{list} ;
    for (my $idx = 0; $idx < $#$list; $idx ++ ) {
	if ($list->[$idx] eq $key1) {
	    $list->[$idx] = $key2 ;
	}
	elsif ($list->[$idx] eq $key2) {
	     $list->[$idx] = $key1 ;
	}
    }
}

=head2 move_up ( key )

Move the key up in a ordered hash. Attempt to move up the first key of
an ordered hash will be ignored. Ignored for non ordered hash.

=cut

sub move_up {
    my $self = shift ;
    my ($key) = @_ ;

    Config::Model::Exception::User
	-> throw (
		  object => $self,
		  message => "move_up: unknow key $key"
		 )
	  unless exists $self->{data}{$key} ;

    my $list = $self->{list} ;
    # we start from 1 as we can't move up idx 0
    for (my $idx = 1; $idx < scalar @$list; $idx ++ ) {
	if ($list->[$idx] eq $key) {
	    $list->[$idx]   = $list->[$idx-1];
	    $list->[$idx-1] = $key ;
	    last ;
	}
    }
}

=head2 move_down ( key )

Move the key down in a ordered hash. Attempt to move up the last key of
an ordered hash will be ignored. Ignored for non ordered hash.

=cut

sub move_down {
    my $self = shift ;
    my ($key) = @_ ;

    Config::Model::Exception::User
	-> throw (
		  object => $self,
		  message => "move_down: unknow key $key"
		 )
	  unless exists $self->{data}{$key} ;

    my $list = $self->{list} ;
    # we end at $#$list -1  as we can't move down last idx
    for (my $idx = 0; $idx < scalar @$list - 1 ; $idx ++ ) {
	if ($list->[$idx] eq $key) {
	    $list->[$idx]   = $list->[$idx+1];
	    $list->[$idx+1] = $key ;
	    last ;
	}
    }
}

=head2 load_data ( hash_ref | array_ref)

Load check_list as a hash ref for standard hash.
Ordered hash must be loaded with a array ref.

=cut

sub load_data {
    my $self = shift ;
    my $data = shift ;
    if (not $self->{ordered} and ref ($data) eq 'HASH') {
	foreach my $elt (keys %$data ) {
	    my $obj = $self->fetch_with_id($elt) ;
	    $obj -> load_data($data->{$elt}) ;
	}
    }
    elsif ( $self->{ordered} and ref ($data) eq 'ARRAY') {
	my $idx = 0 ;
	while ( $idx < @$data ) {
	    my $obj = $self->fetch_with_id($data->[$idx++]) ;
	    $obj -> load_data($data->[$idx++]) ;
	}
    }
    else {
	my $expected = $self->{ordered} ? 'array' : 'hash' ;
	Config::Model::Exception::LoadData
	    -> throw (
		      object => $self,
		      message => "load_data called with non $expected ref arg",
		      wrong_data => $data ,
		     ) ;
    }
}

1;

__END__

=head1 AUTHOR

Dominique Dumont, (ddumont at cpan dot org)

=head1 SEE ALSO

L<Config::Model::Model>, 
L<Config::Model::Instance>, 
L<Config::Model::AnyId>,
L<Config::Model::ListId>,
L<Config::Model::Value>

=cut
