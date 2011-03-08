#!/usr/bin/perl 
package JMX::Jmx4Perl::Agent::Manager::ArtifactHandler;

=head1 NAME

JMX::Jmx4Perl::Agent::ArtifactHandler - Handler for extracting and manipulating
Jolokia artifacts

=cut

use Data::Dumper;
use strict;

use vars qw($HAS_ARCHIVE_ZIP $GLOBAL_ERROR);

BEGIN {
    $HAS_ARCHIVE_ZIP = eval "require Archive::Zip; Archive::Zip->import(qw(:ERROR_CODES)); 1";
    if ($HAS_ARCHIVE_ZIP) {
        Archive::Zip::setErrorHandler( sub {
                                           $GLOBAL_ERROR = join " ",@_;
                                           chomp $GLOBAL_ERROR;
                                       } );
    }
}

sub new { 
    my $class = shift;
    my %args = @_;
    my $file = $args{file};
    my $self = { file => $file, logger => $args{logger}, meta => $args{meta}};
    bless $self,(ref($class) || $class);
    $self->_fatal("No Archive::Zip found. Please install it for handling Jolokia archives.") unless $HAS_ARCHIVE_ZIP;
    $self->_fatal("No file given") unless $file;
    $self->_fatal("No such file $file") unless -e $file;
    return $self;
}


sub info {
    my $self = shift;
    my $file = $self->{file};
    my $jar = $self->_read_archive();
    my @props = $jar->membersMatching('META-INF/maven/org.jolokia/.*?/pom.properties');
    $self->_fatal("Cannot extract pom.properties from $file") unless @props;
    for my $prop (@props) {
        my ($content,$status) = $prop->contents;
        $self->_fatal("Cannot extract pom.properties: ",$GLOBAL_ERROR) unless $status eq AZ_OK();
        my $ret = {};
        for my $l (split /\n/,$content) {
            next if $l =~ /^\s*#/;
            my ($k,$v) = split /=/,$l,2;
            $ret->{$k} = $v;
        }
        $self->_fatal("$file is not a Jolokia archive") unless $ret->{groupId} eq "org.jolokia" ;
        my $type = $self->{meta}->extract_type($ret->{artifactId});
        if ($type) {
            $ret->{type} = $type;
            return $ret;
        }
    }
    return {};
}

sub _read_archive {
    my $self = shift;
    my $file = $self->{file};
    my $jar = new Archive::Zip();
    my $status = $jar->read($file);
    $self->_fatal("Cannot read content of $file: ",$GLOBAL_ERROR) unless $status eq AZ_OK();
    return $jar;
}

sub add_policy {
    my $self = shift;
    my $policy = shift;
    my $file = $self->{file};
    $self->_fatal("No such file $policy") unless -e $policy;
    
    my $jar = $self->_read_archive();
    my $path = $self->_policy_path;
    
    my $existing = $jar->removeMember($path);
    my $res = $jar->addFile($policy,$path);
    $self->_fatal("Cannot add $policy to $file as ",$path,": ",$GLOBAL_ERROR) unless $res;
    my $status = $jar->overwrite();
    $self->_fatal("Cannot write $file: ",$GLOBAL_ERROR) unless $status eq AZ_OK();
    $self->_info($existing ? "Replacing existing policy " : "Adding policy ","[em]",$path,"[/em]",$existing ? " in " : " to ","[em]",$file,"[/em]");
}

sub remove_policy {
    my $self = shift;
    my $policy = shift;
    my $file = $self->{file};
    
    my $jar = $self->_read_archive();
    my $path = $self->_policy_path;
    
    my $existing = $jar->removeMember($path);
    if ($existing) {
        my $status = $jar->overwrite();
        $self->_fatal("Cannot write $file: ",$GLOBAL_ERROR) unless $status eq AZ_OK();    
        $self->_info("Removing policy","[em]",$policy,"[/em]"," in ","[em]",$file,"[/em]");
    } else {
        $self->_info("No policy found, leaving ","[em]",$file,"[/em]"," untouched.");
    }
}

sub has_policy {
    my $self = shift;

    my $jar = $self->_read_archive();
    my $path = $self->_policy_path;
    return $jar->memberNamed($path) ? $path : undef;
}


sub get_policy {
    my $self = shift;

    my $jar = $self->_read_archive();
    my $path = $self->_policy_path;
    return $jar->contents($path);
}

sub extract_webxml {
    my $self = shift;
    my $type = $self->_type;
    $self->_fatal("web.xml can only be read from 'war' archives (not ')",$type,"')") unless $type eq "war";

    my $jar = $self->_read_archive();
    return $jar->contents("WEB-INF/web.xml");
}

sub update_webxml {
    my $self = shift;
    my $webxml = shift;
    my $type = $self->_type;
    $self->_fatal("web.xml can only be updated in 'war' archives (not '",$type,"')") unless $type eq "war";

    my $jar = $self->_read_archive();
    $jar->removeMember("WEB-INF/web.xml");
    my $res = $jar->addString($webxml,"WEB-INF/web.xml");
    $self->_fatal("Cannot update WEB-INF/web.xml: ",$GLOBAL_ERROR) unless $res;
        my $status = $jar->overwrite();
    $self->_fatal("Cannot write ",$self->{file},": ",$GLOBAL_ERROR) unless $status eq AZ_OK();
    $self->_info("Updated ","[em]","web.xml","[/em]"," for ",$self->{file});
}


sub _policy_path {
    my $self = shift;
    return ($self->_type eq "war" ? "WEB-INF/classes/" : "") . "jolokia-access.xml";
}

sub _type {
    my $self = shift;
    my $info = $self->info;
    return $info->{type};
}

sub _fatal {
    my $self = shift;
    $self->{logger}->error(@_);
    die "\n";
}

sub _info {
    my $self = shift;
    $self->{logger}->info(@_);
}
1;