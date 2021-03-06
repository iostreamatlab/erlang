-module(example).

-export([sieve/1]).

%% This implementation incorporates the refinements
%% from https://en.wikipedia.org/wiki/Sieve_of_Eratosthenes

sieve(N) when N<2 ->
	[];
sieve(N) ->
	sieve(lists:seq(3, N, 2), [2], trunc(math:sqrt(N))+1).

sieve([P|Candidates], Acc, StopAt) when P<StopAt ->
	NewCandidates=filter_candidates(P, Candidates),
	sieve(NewCandidates, [P|Acc], StopAt);
sieve(Primes, Acc, _) ->
	lists:reverse(Acc)++Primes.


filter_candidates(P, Candidates) ->
	filter_candidates(P, P*P, Candidates, []).

filter_candidates(_, _, [], Acc) ->
	lists:reverse(Acc);
filter_candidates(P, N, [C|Candidates], Acc) when C=:=N ->
	filter_candidates(P, N+2*P, Candidates, Acc);
filter_candidates(P, N, [C|Candidates], Acc) when C<N ->
	filter_candidates(P, N, Candidates, [C|Acc]);
filter_candidates(P, N, Candidates, Acc) ->
	filter_candidates(P, N+2*P, Candidates, Acc).

