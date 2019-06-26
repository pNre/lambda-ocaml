open Async
open Core
open Cohttp
open Cohttp_async

type error =
  | Request_error of exn
  | Response_error of Response.t * string
  | Handler_error of string

let string_of_error = function
  | Request_error exn -> Exn.to_string exn
  | Response_error (response, _) ->
    let code = Code.code_of_status response.status in
    sprintf "status = %d, headers = %s" code (Header.to_string response.headers)
  | Handler_error error -> error
;;

module Lambda = struct
  type error =
    { error_type : string [@key "errorType"]
    ; error_message : string [@key "errorMessage"]
    ; stack_trace : string [@key "stackTrace"]
    }
  [@@deriving to_yojson { strict = false }, make]

  type context =
    { aws_request_id : string
    ; invoked_function_arn : string option [@default None]
    ; deadline_ms : string option [@default None]
    ; trace_id : string option [@default None]
    ; client_context : string option [@default None]
    ; cognito_identity : string option [@default None]
    }
  [@@deriving make]

  let context_of_response { Response.headers; _ } =
    let aws_request_id =
      Option.value_exn (Header.get headers "lambda-runtime-aws-request-id")
    in
    let invoked_function_arn =
      Header.get headers "lambda-runtime-invoked-function-arn"
    in
    let deadline_ms = Header.get headers "lambda-runtime-deadline-ms" in
    let trace_id = Header.get headers "lambda-runtime-trace-id" in
    let client_context = Header.get headers "lambda-runtime-client-context" in
    let cognito_identity = Header.get headers "lambda-runtime-cognito-identity" in
    make_context
      ~aws_request_id
      ~invoked_function_arn
      ~deadline_ms
      ~trace_id
      ~client_context
      ~cognito_identity
      ()
  ;;

  let runtime_path = "/2018-06-01/runtime"

  module Env = struct
    let host_and_port =
      "AWS_LAMBDA_RUNTIME_API" |> Sys.getenv_exn |> Host_and_port.of_string
    ;;

    let log_group_name = "AWS_LAMBDA_LOG_GROUP_NAME" |> Sys.getenv
    let log_stream_name = "AWS_LAMBDA_LOG_STREAM_NAME" |> Sys.getenv
    let function_name = "AWS_LAMBDA_FUNCTION_NAME" |> Sys.getenv
    let function_version = "AWS_LAMBDA_FUNCTION_VERSION" |> Sys.getenv
    let function_memory_size = "AWS_LAMBDA_FUNCTION_MEMORY_SIZE" |> Sys.getenv
  end
end

let request_uri path =
  Uri.make
    ~scheme:"http"
    ~host:Lambda.Env.host_and_port.host
    ~port:Lambda.Env.host_and_port.port
    ~path
    ()
;;

let request http_method uri ?(http_headers = []) ?(body = None) () =
  let call =
    try_with (fun _ ->
        Client.call
          ~headers:(Header.of_list http_headers)
          ~body:(Option.value_map body ~default:`Empty ~f:Body.of_string)
          http_method
          uri)
  in
  call
  >>| Result.map_error ~f:(fun e -> Request_error e)
  >>=? (fun (response, body) ->
         body |> Body.to_string >>| fun body -> Result.return (response, body))
  >>=? function
  | ({ status; _ } as response), body when Code.is_success (Code.code_of_status status)
    ->
    Deferred.Result.return (response, body)
  | response, body -> Response_error (response, body) |> Deferred.Result.fail
;;

let invocation_response ~context ~response =
  let uri =
    request_uri
      (Lambda.runtime_path ^ "/invocation/" ^ context.Lambda.aws_request_id ^ "/response")
  in
  request `POST uri ~body:(Some response) ()
;;

let invocation_error ~context ~error =
  let headers =
    [ "Content-Type", "application/json"
    ; "Lambda-Runtime-Function-Error-Type", error.Lambda.error_type
    ]
  in
  let uri =
    request_uri
      (Lambda.runtime_path ^ "/invocation/" ^ context.Lambda.aws_request_id ^ "/error")
  in
  let json = error |> Lambda.error_to_yojson |> Yojson.Safe.to_string in
  request `POST uri ~http_headers:headers ~body:(Some json) ()
;;

let next_invocation handler =
  let uri = request_uri (Lambda.runtime_path ^ "/invocation/next") in
  request `GET uri ()
  >>|? (fun (response, body) ->
         Lambda.context_of_response response, Yojson.Safe.from_string body)
  >>=? fun (context, body) ->
  handler context body
  >>= function
  | Ok response -> invocation_response ~context ~response
  | Error error -> invocation_error ~context ~error
;;

let test_handler _context _body = Deferred.Result.return "🐫"

let () =
  Deferred.forever () (fun () -> next_invocation test_handler >>| ignore);
  never_returns (Scheduler.go ())
;;
