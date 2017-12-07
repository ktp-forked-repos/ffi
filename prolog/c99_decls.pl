:- module(c99_decls,
          [ c99_header_ast/2,                   % +Header, -AST
            c99_types/3                         % +Header, +Functions, -AST
          ]).
:- use_module(library(process)).
:- use_module(library(pure_input)).
:- use_module(library(apply)).
:- use_module(library(lists)).
:- use_module(c99_phrase).

%!  c99_types(+Header, +Functions, -AST)
%
%

c99_types(Header, Functions, Types) :-
    c99_header_ast(Header, AST),
    phrase(prototypes(Functions, AST), Types).

prototypes([], _) --> [].
prototypes([H|T], AST) --> prototype(H, AST), prototypes(T, AST).

prototype(Func, AST) -->
    { skeleton(prototype(Return, RDecl, Params0), Func, FuncDecl),
      memberchk(FuncDecl, AST),
      maplist(param, Params0, Params),
      memberchk(type(BasicType), Return),
      pointers(RDecl, BasicType, RType)
    },
    [ function(Func, RType, Params) ],
    type_opt(RType, AST),
    types(Params, AST).

%!  skeleton(+Type, +Id, -Skeleton)
%
%   AST skeleton to find the definition of Id of type Type

skeleton(prototype(Return, RDecl, Params), Func,
         decl(Return,
              [ declarator(RDecl, dd(Func, dds(Params)))
              ],
              _Attributes)).

param(param(Specifiers, declarator(Decl, dd(Name,_))), Name-Type) :-
    memberchk(type(BasicType), Specifiers),
    pointers(Decl, BasicType, Type).

pointers(-, Type, Type).
pointers([], Type, Type).
pointers([ptr(_)|T], Basic, Type) :-
    pointers(T, *(Basic), Type).


		 /*******************************
		 *      TYPE DEFINITIONS	*
		 *******************************/

types([], _) --> [].
types([H|T], AST) --> type_opt(H, AST), types(T, AST).

type_opt(Type, AST) -->
    type(Type, AST), !.
type_opt(_, _) --> [].

type(_Name-Type, AST) --> !, type(Type, AST).
type(*(Type), AST) --> !, type(Type, AST).
type(Type, AST) -->
    { ast_type(Type, AST, Defined) },
    [ Defined ],
    type(Defined, AST).
type(type(Type), AST) -->
    type(Type, AST).
type(type(_, struct, Fields), AST) -->
    types(Fields, AST).
type(f(Types, _Declarator, _Attrs), AST) -->
    types(Types, AST).
type(type(_, typedef, Types), AST) -->
    types(Types, AST).

ast_type(struct(Name), AST, type(Name, struct, Fields)) :-
    member(decl(Specifier, _Decl, _Attrs), AST),
    memberchk(type(struct(Name, Fields)), Specifier), !.
ast_type(user_type(Name), AST, type(Name, typedef, Primitive)) :-
    member(decl(Specifier,
                [ declarator(_, dd(Name, _))], _Attrs), AST),
    selectchk(storage(typedef), Specifier, Primitive), !.


		 /*******************************
		 *       CALL PREPROCESSOR	*
		 *******************************/

%!  c99_header_ast(+Header, -AST)

c99_header_ast(Header, AST) :-
    setup_call_cleanup(
        open_gcc_cpp(Header, In),
        phrase_from_stream(c99_parse(AST), In),
        close(In)).

open_gcc_cpp(Header, Out) :-
    process_create(path(gcc), ['-E', '-xc', -],
                   [ stdin(pipe(In)),
                     stdout(pipe(Out))
                   ]),
    thread_create(
        setup_call_cleanup(
            open_string(Header, HIn),
            copy_stream_data(HIn, In),
            (   close(HIn),
                close(In)
            )), _, [detached(true)]).