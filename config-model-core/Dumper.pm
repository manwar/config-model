# $Author: ddumont $
# $Date: 2007-02-23 12:55:16 $
# $Name: not supported by cvs2svn $
# $Revision: 1.14 $

#    Copyright (c) 2006-2007 Dominique Dumont.
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

package Config::Model::Dumper;
use Carp;
use strict;
use warnings ;

use Config::Model::Exception ;
use Config::Model::ObjTreeScanner ;

use vars qw($VERSION);
$VERSION = sprintf "%d.%03d", q$Revision: 1.14 $ =~ /(\d+)\.(\d+)/;

=head1 NAME

Config::Model::Dumper - Serialize data of config tree

=head1 SYNOPSIS

 use Config::Model ;

 # create your config model
 my $model = Config::Model -> new ;
 $model->create_config_class( ... ) ;

 # create instance
 my $inst = $model->instance (root_class_name => 'FooBar', 
			      instance_name => 'test1');

 # create root of config
 my $root = $inst -> config_root ;

 # put some data in config tree
 my $step = 'std_id:ab X=Bv - std_id:bc X=Av - a_string="toto tata"';
 $root->walk( step => $step ) ;

 # dump only customized data (audit mode)
 print $root->dump_tree;

 # dump all data including default values
 print $root->dump_tree( full_dump => 1 ) ;

=head1 DESCRIPTION

This module is used directly by L<Config::Model::Node> to serialize 
configuration data in a compact (but readable) string.

The serialisation can be done in standard mode where only customized
values are dumped in the string. I.e. only data modified by the user
are dumped.

The other mode is C<full_dump> mode where all all data, including
default values, are dumped.

The serialized string can be used by L<Config::Model::Walker> to store
the data back into a configuration tree.

=head1 CONSTRUCTOR

=head2 new ( )

No parameter. The constructor should be used only by
L<Config::Model::Node>.

=cut

sub new {
    bless {}, shift ;
}

=head1 Methods

=head2 dump_tree

Return a string that contains a dump of the object tree with all the
values. This string follows the convention defined by
L<Config::Model::Walker>.

The serialized string can be used by L<Config::Model::Walker> to store
the data back into a configuration tree.

Parameters are:

=over

=item full_dump

Set to 1 to dump all configuration data including default
values. Default is 0, where the dump contains only data modified by
the user (i.e. data differ from default values).

=item node

Reference to the L<Config::Model::Node> object that is dumped. All
nodes and leaves attached to this node are also dumped.

=back

=cut

sub dump_tree {
    my $self = shift;

    my %args = @_;
    my $full = delete $args{full_dump} || 0;
    my $node = delete $args{node} 
      || croak "dump_tree: missing 'node' parameter";

    my $compute_pad = sub {
	my $depth = 0 ;
	my $obj = shift ;
	while (defined $obj->parent) { 
	    $depth ++ ;
	    $obj = $obj->parent ;
	}
        return '  ' x $depth;
    };

    my $std_cb = sub {
        my ( $scanner, $data_r, $obj, $element, $index, $value_obj ) = @_;

	# get value or only customized value
	my $value = $full ? $value_obj->fetch : $value_obj->fetch_custom;

        $value = '"' . $value . '"' if defined $value and $value =~ /\s/;

        my $pad = $compute_pad->($obj);

        my $name = defined $index && $index =~ /\s/ ? "$element:\"$index\"" 
	         : defined $index                   ? "$element:$index" 
                 :                                     $element;

        $$data_r .= "\n" . $pad . $name . '=' . $value if defined $value;
    };

    my $list_element_cb = sub {
        my ( $scanner, $data_r, $obj, $element, @keys ) = @_;

        my $pad      = $compute_pad->($obj);
	my $list_obj = $obj->fetch_element($element) ;
        my $elt_type = $list_obj->cargo_type ;

        if ( $elt_type eq 'node' ) {
            foreach my $k ( @keys ) {
                $scanner->scan_hash( $data_r, $obj, $element, $k );
            }
        }
        else {
            $$data_r .= "\n$pad$element=" 
	      . join( ',', $list_obj->fetch_all_values ) if @keys;
        }
    };

    my $element_cb = sub {
        my ( $scanner, $data_r, $obj, $element, $key, $next ) = @_;

        my $type = $obj -> element_type($element);

        # return if $$data_r and $next->isa('Config::Model::AutoRead');

        my $pad = $compute_pad->($obj);
        $$data_r .= "\n$pad$element";
	if ($type eq 'list' or $type eq 'hash') {
	    $key = '"' . $key . '"' if  $key =~ /\s/;
	    $$data_r .= ":$key" ;
	}

        $scanner->scan_node($data_r, $next);
    };

    my @scan_args = (
		     permission      => delete $args{permission} || 'master',
		     fallback        => 'all',
		     auto_vivify     => 0,
		     list_element_cb => $list_element_cb,
		     leaf_cb         => $std_cb,
		     node_element_cb => $element_cb,
		     up_cb           => sub { ${$_[1]} .= ' -'; }
		    );

    my @left = keys %args;
    croak "Dumper: unknown parameter:@left" if @left;

    # perform the scan
    my $view_scanner = Config::Model::ObjTreeScanner->new(@scan_args);

    my $ret = '' ;
    $view_scanner->scan_node(\$ret, $node);

    substr( $ret, 0, 1, '' );    # remove leading \n
    return $ret . "\n";
}

1;

=head1 AUTHOR

Dominique Dumont, (ddumont at cpan dot org)

=head1 SEE ALSO

L<Config::Model>,L<Config::Model::Node>,L<Config::Model::Walker>
