(***********************************************************************)
(*                                                                     *)
(*    Copyright 2012 OCamlPro                                          *)
(*    Copyright 2012 INRIA                                             *)
(*                                                                     *)
(*  All rights reserved.  This file is distributed under the terms of  *)
(*  the GNU Public License version 3.0.                                *)
(*                                                                     *)
(*  TypeRex is distributed in the hope that it will be useful,         *)
(*  but WITHOUT ANY WARRANTY; without even the implied warranty of     *)
(*  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the      *)
(*  GNU General Public License for more details.                       *)
(*                                                                     *)
(***********************************************************************)

open Types

let log fmt = Globals.log "REPO" fmt

let run cmd repo args =
  log "opam-%s: %s %s" cmd (Repository.to_string repo) (String.concat " " args);
  let path = Path.R.root (Path.R.create repo) in
  let cmd =  Printf.sprintf "opam-%s-%s" (Repository.kind repo) cmd in
  let i = Run.in_dir (Dirname.to_string path) (fun () ->
    Run.command ( cmd :: Dirname.to_string (Repository.address repo) :: args );
  ) in
  if i <> 0 then
    Globals.error_and_exit "%s failed" cmd

let init r =
  let root = Path.R.create r in
  Dirname.mkdir (Path.R.root root);
  run "init" r [];
  File.Repo_config.write (Path.R.config root) r;
  Dirname.mkdir (Path.R.packages_dir root);
  Dirname.mkdir (Path.R.archives_dir root);
  Dirname.mkdir (Path.R.compilers_dir root);
  Dirname.mkdir (Path.R.upload_dir root)

let update r =
  run "update" r []

let upload r =
  run "upload" r []

type download_info = {
  local_path     : dirname;
  remote_filename: filename;
  nv             : nv;
}

let string_of_download_info d =
  Printf.sprintf "<remote_filename=%s nv=%s>" 
    (Filename.to_string d.remote_filename) (NV.to_string d.nv)

let read_download_info () =
  if Array.length Sys.argv <> 3 then (
    Printf.eprintf "Usage: %s <remote-filename> <package>" Sys.argv.(0);
    exit 1
  );
  let local_path = Dirname.cwd () in
  let remote_filename = Filename.of_string Sys.argv.(1) in
  let nv = NV.of_string Sys.argv.(2) in
  { local_path; remote_filename; nv }

type file = D of dirname | F of filename | UpToDate

let file filename =
  if not (Sys.is_directory filename) then
    F (Filename.of_string filename)
  else
    D (Dirname.of_string filename)

let download_one kind d =
  let cmd = Printf.sprintf "opam-%s-download" kind in
  let output = Dirname.in_dir d.local_path (fun () ->
    Run.read_command_output [
      cmd; Filename.to_string d.remote_filename; NV.to_string d.nv;
    ]) in
  match output with
  | None        -> None
  | Some []     -> Some UpToDate
  | Some (f::_) -> Some (file f)

let rec download_iter local_path nv = function
  | [] -> None
  | (remote_filename ,kind) :: t ->
      let d = { local_path; remote_filename; nv } in
      match download_one kind d with
      | None -> download_iter local_path nv t
      | r    -> r

let kind_of_repository r =
  if Dirname.exists (Repository.address r) then "rsync" else "curl"

(* Download the archive on the OPAM server.
   If it is not there, then:
   * download the original archive upstream
   * add eventual patches
   * create a new tarball *)
let download r nv =
  log "download %s %s" (Repository.to_string r) (NV.to_string nv);
  let remote_repo = Path.R.of_dirname (Repository.address r) in
  let local_repo = Path.R.create r in

  (* If the archive is on the server, download it directly *)
  let remote_filename = Path.R.archive remote_repo nv in
  let kind = kind_of_repository r in
  let d = {
    local_path = Path.R.archives_dir local_repo;
    remote_filename;
    nv;
  } in
  match download_one kind d with
  | Some UpToDate ->
      log "%s is already downloaded and up-to-date"
        (Filename.to_string remote_filename);
  | Some (F local_file) ->
      log "Downloaded %s" (Filename.to_string local_file)
  | Some (D _) ->
      Globals.error_and_exit
        "Got unexpected folder while downloading %s"
        (Filename.to_string remote_filename)
  | None   ->
      log
        "%s is not on the server, need to build it"
        (Filename.to_string remote_filename);
      let url_f = Path.R.url local_repo nv in
      let tmp_dir = Path.R.tmp_dir local_repo nv in
      let extract_dir = tmp_dir / NV.to_string nv in
      Dirname.mkdir tmp_dir;

      if Filename.exists url_f then begin
        (* download the archive upstream if the upstream address
           is specified *)
        let urls = File.URL.read url_f in
        let urls =
          List.map (function
            | (f,Some k) -> (f,k)
            | (f,None)   -> (f, kind)
          ) urls in
        let urls_s =
          String.concat " "
            (List.map
               (fun (f,k) -> Printf.sprintf "%s:%s" (Filename.to_string f) k)
               urls) in
        log "downloading %s" urls_s;
        match download_iter tmp_dir nv urls with

        | None -> Globals.error_and_exit "Cannot get %s" urls_s

        | Some UpToDate -> ()

        | Some (F local_archive) ->
            log "extracting %s to %s"
              (Filename.to_string local_archive)
              (Dirname.to_string tmp_dir);
            Filename.extract local_archive extract_dir

        | Some (D local_dir) ->
            log "copying %s to %s"
              (Dirname.to_string local_dir)
              (Dirname.to_string tmp_dir);
            if local_dir <> extract_dir then
              Dirname.move local_dir extract_dir
        end;
            
        (* Eventually add the files/<package>/* to the extracted dir *)
        log "Adding the files to the archive";
        let files = Path.R.available_files local_repo nv in
        List.iter (fun f -> Filename.copy_in f extract_dir) files;

        (* And finally create the final archive *)
        (* XXX: we should add a suffix to the version to show that
           the archive has been repacked by opam *)
        let local_archive = Path.R.archive local_repo nv in
        log "Creating the archive files in %s" (Filename.to_string local_archive);
        let err = Dirname.exec tmp_dir [
          [ "tar" ; "czf" ; Filename.to_string local_archive ; NV.to_string nv ]
        ] in
        if err <> 0 then
          Globals.error_and_exit "Cannot compress %s" (Dirname.to_string tmp_dir)

(* check whether an archive have changed *)
