(**************************************************************************)
(*                                                                        *)
(*    Copyright 2012-2015 OCamlPro                                        *)
(*    Copyright 2012 INRIA                                                *)
(*                                                                        *)
(*  All rights reserved.This file is distributed under the terms of the   *)
(*  GNU Lesser General Public License version 3.0 with linking            *)
(*  exception.                                                            *)
(*                                                                        *)
(*  OPAM is distributed in the hope that it will be useful, but WITHOUT   *)
(*  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY    *)
(*  or FITNESS FOR A PARTICULAR PURPOSE.See the GNU General Public        *)
(*  License for more details.                                             *)
(*                                                                        *)
(**************************************************************************)

(** Repository sub-command functions. *)

open OpamStateTypes
open OpamTypes

(** Update the given repository from its upstream. Returns a concurrency-safe
    state update function *)
val update: global_state -> repository ->
  (repos_state -> repos_state) OpamProcess.job

(** Update the package index. *)
val update_package_index: repos_state -> repos_state

(** Update the compiler index. *)
val update_compiler_index: repos_state -> repos_state

(** Update the given dev packages. *)
val update_dev_packages: switch_state -> verbose:bool -> package_set -> package_set

(** Fix the compiler descriptions and display the changes if [verbose]
    is set. *)
val fix_compiler_descriptions: repos_state -> verbose:bool -> compiler_set updates

(** Fix the the package descriptions and display the changes if
    [verbose] is set. *)
val fix_package_descriptions: repos_state -> verbose:bool -> package_set updates

(** Fix all the package and compiler descriptions. *)
val fix_descriptions: ?save_cache:bool -> ?verbose:bool -> repos_state -> unit

(** List the available repositories. *)
val list: short:bool -> unit

(** Add a new repository. *)
val add: repository_name -> url -> priority:int option -> unit

(** Remove a repository. *)
val remove: repository_name -> unit

(** Set a repository priority. *)
val priority: repository_name -> priority:int -> unit

(** Change the registered address of a repo *)
val set_url: repository_name -> url -> unit
