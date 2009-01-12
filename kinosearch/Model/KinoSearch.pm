use KinoSearch::Simple;

our %KS;
our %Searcher;
our %QueryParser;
our $Language = 'en';

event->register(
   'name' => 'request-prepare-end',
   'method' => class method {
      my $l = request->language;
      my $languages = config('kinosearch')->{'languages'};
      if (grep { $_ eq $l } @$languages) {
         $class->language(request->language)
      } else {
         $class->language(config('kinosearch')->{'default-language'} || 'en');
      }
   },
);

class method language($language) {
   $Language = $language if $language;
   return $Language;
}

class method init($name, $fields) {
   return if $KS{app->name}{$name};
   my $name2 = $name;
   $name2 =~ s/\W/_/g;
   my $fields2 = join ", ", map "'$_' => 'text'", @$fields;
   foreach my $language (@{config('kinosearch')->{'languages'}}) {
      my $schema = "app::Model::KinoSearch::Schema::$name2::$language";
      eval qq{
         package $schema;
         use base qw( KinoSearch::Schema );
         our \%fields = ( $fields2 );
         sub analyzer { 
            KinoSearch::Analysis::PolyAnalyzer->new('language' => '$language');
         }
      };
      $schema = $schema->new;
      mkdir config('kinosearch')->{'path'};
      mkdir config('kinosearch')->{'path'} . "/$name2";
      my $path = config('kinosearch')->{'path'} . "/$name2";
      my $index = $schema->read($path);
      $KS{app->name}{$name}{$language} = {
         'path' => $path,
         'fields' => $fields,
         'index' => $index,
         'schema' => $schema,
         'indexer' => undef,
         'indent' => 0,
      };
   }
}

class method ks($name, $language) {
   my $ks = $KS{app->name}{$name}{$language};
   assert $ks, "kinosearch not initialized for name/language '$name/$language'";
   return $ks;
}

class method import(%params) {
   my $caller = caller;
   my $fields = $params{'fields'};
   assert $fields, "no fields defined";
   
   #... init index
   $class->init($caller, $fields);

   #... create model accessors
   # if (keys %{$params{'columns'}}) {
   #    my $fields = delete $fields{'fields'} || [];
   # 
   #    event->register(
   #       'name' => "$caller-after-save",
   #       'method' => class method($obj) {
   #          app::Model::KinoSearch->start_update;      
   #          app::Model::KinoSearch->delete(
   #             'id' => $obj->id,
   #             'class' => ref($obj),
   #          );
   #          app::Model::KinoSearch->add(
   #             'id' => $obj->id,
   #             'class' => ref($class),
   #             map { $_ => $obj->$_ } @$fields,
   #             map { $_ => $fields{$_}->($obj) } keys %fields,
   #          );
   #          app::Model::KinoSearch->finish_update;      
   #       },
   #    );
   #
   #    event->register(
   #       'name' => "$caller-after-delete",
   #       'method' => class method($obj) {
   #          app::Model::KinosSearch->delete(
   #             'id' => $obj->id,
   #             'class' => ref($obj),
   #          );
   #       },
   #    );
   #
   #    WebTek::Util::make_method($caller, 'kinosearch', class method(%p) {
   #       my $q = $p{'query'} + " AND class:$class";
   #       my $r = app::Model::KinosSearch->search($q, $p{'offset'}, $p{'limit'});
   #       return [ map $class->new_default($_), @$r ];
   #    });
   # }
}

class method start_update(%params) {
   my $name = $params{'name'} || caller;
   my $language = $params{'language'} || $Language;   
   my $ks = $class->ks($name, $language);
   unless ($ks->{'indent'}++) {
      $ks->{'indexer'} =
         KinoSearch::InvIndexer->new('invindex' => $ks->{'index'});      
   };
}

class method finish_update(%params) {
   my $name = $params{'name'} || caller;
   my $language = $params{'language'} || $Language;   
   my $ks = $class->ks($name, $language);
   $ks->{'indexer'}->finish unless --$ks->{'indent'};
   my $dir = config('kinosearch')->{'path'};
   `chmod -R 777 $dir`;
}

class method add(%params) {
   my $name = $params{'name'} || caller;
   my $language = $params{'language'} || $Language;
   my $document = $params{'document'};
   assert $document, "no document defined to add";

   $class->start_update('name' => $name, 'language' => $language);
   $class->ks($name, $language)->{'indexer'}->add_doc($document);
   $class->finish_update('name' => $name, 'language' => $language);
}

class method delete(%params) {
   my $name = $params{'name'} || caller;
   my $language = $params{'language'} || $Language;
   my $document = $params{'document'};
   assert $document, "no document defined to delete";

   $class->start_update('name' => $name, 'language' => $language);
   $class->ks($name, $language)->delete_by_term(%$document);
   $class->finish_update('name' => $name, 'language' => $language);
}

class method search(%params) {
   my $name = $params{'name'} || caller;
   my $language = $params{'language'} || $Language;
   my $query = $params{'query'};
   assert $query, "no query defined";

   # get searcher, queryparser
   my $ks = $class->ks($name, $language);
   $ks->{'searcher'} ||=
      KinoSearch::Searcher->new('invindex' => $ks->{'index'});
   $ks->{'query_parser'} ||= KinoSearch::QueryParser->new(
      schema => $ks->{'schema'},
      fields => $ks->{'fields'},
   );
   $ks->{'query_parser'}->set_heed_colons(1);

   #... do the search
   my %search = ( 'query' => $ks->{'query_parser'}->parse($query) );
   $search{'offset'} = $params{'offset'} if exists $params{'offset'};
   $search{'num_wanted'} = $params{'limit'} if exists $params{'limit'};
	my $hits = $ks->{'searcher'}->search(%search);
   my $result = [];
   while (my $hit = $hits->fetch_hit_hashref) { push @$result, $hit }
   return $result;
}
