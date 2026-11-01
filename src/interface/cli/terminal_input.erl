-module(terminal_input).
-export([read_line/0]).

read_line() ->
    case io:get_line("") of
        eof ->
            {error, nil};

        {error, _Reason} ->
            {error, nil};

        Line ->
            {ok, string:trim(Line)}
    end.