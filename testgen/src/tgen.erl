-module(tgen).

-export([
    check/1,
    generate/1,
    to_test_name/1,
    to_property_name/1
]).

-export_type([
    tgen/0,
    exercise_json/0
]).

-include("tgen.hrl").

-type tgen() :: #tgen{}.

% -type canonical_data() :: #{
%     exercise := binary(),
%     version  := binary(),
%     cases    := exercise_json()
% }.

-type exercise_json() :: #{
    description := binary(),
    expected    := jsx:json_term(),
    property    := binary(),
    binary()    => jsx:json_term()
}.

-callback available() -> boolean().
-callback generate_test(exercise_json()) ->
    {ok,
        erl_syntax:syntax_tree() | [erl_syntax:syntax_tree()],
        [{string() | binary(), non_neg_integer()}]}.


-spec check(string()) -> {true, atom()} | false.
check(Name) ->
    Module = list_to_atom("tgen_" ++ Name),
    try Module:available() of
        true -> {true, Module};
        false -> false
    catch
        _:_ -> false
    end.

-spec generate(tgen()) -> ok.
generate(Generator = #tgen{}) ->
    io:format("Generating ~s", [Generator#tgen.name]),
    case file:read_file(Generator#tgen.path) of
        {ok, Content} ->
            Files = process_json(Generator, Content),
            io:format(", finished~n"),
            Files;
        {error, Reason} ->
            io:format(", failed (~p)~n", [Reason]),
            {error, Reason, Generator#tgen.path}
    end.

process_json(G = #tgen{name = GName}, Content) when is_list(GName) ->
    process_json(G#tgen{name = list_to_binary(GName)}, Content);
process_json(#tgen{name = GName, module = Module}, Content) ->
    case jsx:decode(Content, [return_maps, {labels, attempt_atom}]) of
        _JSON = #{exercise := GName, cases := Cases, version := TestVersion} ->
            % io:format("Parsed JSON: ~p~n", [JSON]),
            {TestImpls0, Props} = lists:foldl(fun (Spec, {Tests, OldProperties}) ->
                {ok, Test, Properties} = Module:generate_test(Spec),
                {[Test|Tests], combine(OldProperties, Properties)}
            end, {[], []}, Cases),
            TestImpls1 = lists:reverse(TestImpls0),
            {TestModuleName, TestModuleContent} = generate_test_module(binary_to_list(GName), TestImpls1, binary_to_list(TestVersion)),
            {StubModuleName, StubModuleContent} = generate_stub_module(binary_to_list(GName), Props),

            [#{exercise => GName, name => TestModuleName, folder => "test", content => io_lib:format("~s", [TestModuleContent])},
             #{exercise => GName, name => StubModuleName, folder => "src",  content => io_lib:format("~s", [StubModuleContent])}];
        #{exercise := Name} ->
            io:format("Name in JSON (~p) and name for generator (~p) do not line up", [Name, GName])
    end.



-spec to_test_name(string() | binary()) -> string() | binary().
to_test_name(Name) when is_binary(Name) ->
    to_test_name(binary_to_list(Name));
to_test_name(Name) when is_list(Name) ->
    slugify(Name) ++ "_test".

-spec to_property_name(string() | binary()) -> string() | binary().
to_property_name(Name) when is_binary(Name) ->
    to_property_name(binary_to_list(Name));
to_property_name(Name) when is_list(Name) ->
    slugify(Name).

slugify(Name) when is_binary(Name) -> list_to_binary(slugify(binary_to_list(Name)));
slugify(Name) when is_list(Name) -> slugify(Name, false, []).

slugify([], _, Acc) -> lists:reverse(Acc);
slugify([$_|Name], _, Acc) -> slugify(Name, false, [$_|Acc]);
slugify([$-|Name], _, Acc) -> slugify(Name, false, [$_|Acc]);
slugify([$\s|Name], _, Acc) -> slugify(Name, false, [$_|Acc]);
slugify([C|Name], _, Acc) when C>=$a andalso C=<$z -> slugify(Name, true, [C|Acc]);
slugify([C|Name], _, Acc) when C>=$0 andalso C=<$9 -> slugify(Name, true, [C|Acc]);
slugify([C|Name], false, Acc) when C>=$A andalso C=<$Z -> slugify(Name, false, [C-$A+$a|Acc]);
slugify([C|Name], true, Acc) when C>=$A andalso C=<$Z -> slugify(Name, false, [C-$A+$a, $_|Acc]);
slugify([_|Name], AllowSnail, Acc) -> slugify(Name, AllowSnail, Acc).

generate_stub_module(ModuleName, Props) ->
    SluggedModName = slugify(ModuleName),

    Funs = lists:map(fun
            ({Name, []}) ->
                tgs:simple_fun(Name, [tgs:atom(undefined)]);
            ({Name, Args}) when is_list(Args) ->
                UnderscoredArgs = lists:map(fun (Arg) -> [$_ | Arg] end, Args),
                tgs:simple_fun(Name, UnderscoredArgs, [tgs:atom(undefined)])
        end, Props),

    Abstract = [
        tgs:module(SluggedModName),
        nl,
        tgs:export(Props),
        nl,
        nl
    ] ++ inter(nl, Funs),

    {SluggedModName, lists:flatten(
        lists:map(
            fun (nl) -> io_lib:format("~n", []);
                (Tree) -> io_lib:format("~s~n", [erl_prettypr:format(Tree)])
            end, Abstract))}.

generate_test_module(ModuleName, Tests, TestVersion) ->
    SluggedModName = slugify(ModuleName),

    Abstract = [
        erl_syntax:comment(
		[
			"% Based on canonical data version " ++ TestVersion,
			"% https://github.com/exercism/problem-specifications/raw/master/exercises/" ++ ModuleName  ++ "/canonical-data.json",
        		"% This file is automatically generated from the exercises canonical data."
		]
	),
        tgs:module(SluggedModName ++ "_tests"),
        nl,
        tgs:include_lib("erl_exercism/include/exercism.hrl"),
        tgs:include_lib("eunit/include/eunit.hrl"),
        nl,
        nl] ++ inter(nl, lists:flatten(Tests)),

    {SluggedModName ++ "_tests", lists:flatten(
        lists:map(
            fun (nl) -> io_lib:format("~n", []);
                (Tree) -> io_lib:format("~s~n", [erl_prettypr:format(Tree)])
            end, Abstract))}.

inter(_, []) -> [];
inter(_, [X]) -> [X];
inter(Delim, [X|Xs]) -> [X, Delim|inter(Delim, Xs)].

combine(List, []) -> List;
combine(List, [{Name, Arity}|Xs]) when is_list(Name) ->
    combine(List, [{list_to_binary(Name), Arity}|Xs]);
combine(List, [{Name, _} = X|Xs]) when is_binary(Name) ->
    List1 = insert(List, X),
    combine(List1, Xs).

insert([], X) -> [X];
insert([X|_] = Xs, X) -> Xs;
insert([X|XS], Y) when X < Y -> [X|insert(XS, Y)];
insert([X|XS], Y) when X > Y -> [Y, X|XS].
