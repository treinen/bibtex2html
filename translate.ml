(*
 * bibtex2html - A BibTeX to HTML translator
 * Copyright (C) 1997 Jean-Christophe FILLIATRE
 * 
 * This software is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public
 * License version 2, as published by the Free Software Foundation.
 * 
 * This software is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * 
 * See the GNU General Public License version 2 for more details
 * (enclosed in the file GPL).
 *)

(* $Id: translate.ml,v 1.21 1999-02-04 16:21:50 filliatr Exp $ *)

(* options *)

let nodoc = ref false
let nokeys = ref false
let suffix = ref ".html"
let title = ref ""
let title_spec = ref false
let print_abstract = ref true
let print_footer = ref true

let (fields : string list ref) = ref []
let add_field s = fields := s :: !fields

let debug = ref false

(* first pass to get the crossrefs *)

let (cite_tab : (string,string) Hashtbl.t) = Hashtbl.create 17

let cpt = ref 0

let first_pass bl =
  let rec pass = function
      [] -> ()
    | (None,_,(_,k,_))::rem ->
	incr cpt;
	Hashtbl.add cite_tab k (string_of_int !cpt);
	pass rem
    | (Some c,_,(_,k,_))::rem ->
	Hashtbl.add cite_tab k c;
	pass rem
  in
    cpt := 0;
    Hashtbl.clear cite_tab;
    List.iter (fun (_,items) -> pass items) bl


(* latex2html : to print LaTeX strings in HTML format *)

open Latexmacros

let in_summary = ref false
let directory = ref ""

let cite k =
  try
    let url =
      if !in_summary then 
	Printf.sprintf "#%s" k
      else
	Printf.sprintf "%s%s#%s" !directory !suffix k in
    let c = Hashtbl.find cite_tab k in
      print_s (Printf.sprintf "<A HREF=\"%s\">[%s]</A>" url c)
  with
      Not_found -> print_s "[?]"

let _ = def "\\cite" [ Raw_arg cite ]
let _ = def "\\etalchar" [ Print "<sup>" ; Raw_arg print_s ; Print "</sup>" ]
let _ = def "\\newblock" [Print " "]

let r = Str.regexp "[ \t\n]+"
let remove_whitespace u = Str.global_replace r "" u

let latex_url u =
  let u = remove_whitespace u in
  print_s (Printf.sprintf "<A HREF=\"%s\">%s</A>" u u)
  
let _ = def "\\url" [Raw_arg latex_url]

let latex2html ch s =
  Latexmacros.out_channel := ch;
  Latexscan.brace_nesting := 0;
  Latexscan.main (Lexing.from_string s)

let safe_title e =
  try Bibtex.get_title e with Not_found -> "No title"


(* header and footer of HTML files *)

let own_address = "http://www.lri.fr/~filliatr/bibtex2html/"

let header ch =
  Printf.fprintf ch "
<!-- This document was automatically generated with bibtex2html
     (see http://www.lri.fr/~filliatr/bibtex2html/),
     with the following command:
     ";
  Array.iter (Printf.fprintf ch "%s ") Sys.argv;
  Printf.fprintf ch " -->\n\n"

let footer ch =
  Html.open_balise ch "HR";
  Html.open_balise ch "I";
  output_string ch "This file has been generated by ";
  Html.open_href ch own_address;
  output_string ch "bibtex2html";
  Html.close_href ch

(* links (other than BibTeX entry, when available) *)

let file_type f =
  if List.exists (fun s -> Filename.check_suffix f s) 
    [ ".dvi" ; ".dvi.gz" ; ".dvi.Z" ] then 
    "DVI"
  else if List.exists (fun s -> Filename.check_suffix f s) 
    [ ".ps" ; ".ps.gz" ; ".ps.Z" ] then
    "PS"
  else
    "Available here"

let rec is_url s =
  (String.length s > 3 & String.lowercase (String.sub s 0 4) = "http")
  or  (String.length s > 2 & String.lowercase (String.sub s 0 3) = "ftp")
  or  (String.length s > 3 & String.lowercase (String.sub s 0 4) = "www:")

let get_url s =
  if (String.length s > 3 & String.lowercase (String.sub s 0 4) = "www:") then
    String.sub s 4 (String.length s - 4)
  else
    s

let make_links ch ((t,k,_) as e) =
  (* URL's *)
  List.iter (fun u -> 
	       try
		 let u = Bibtex.get_field e u in
		 let s = file_type u in
		   output_string ch ", ";
		   Html.open_href ch (get_url u);
		   output_string ch s;
		   Html.close_href ch
	       with Not_found -> ())
    (!fields @ 
     [ "FTP"; "HTTP"; "URL" ; "DVI" ; "PS" ; 
       "DOCUMENTURL" ; "URLPS" ; "URLDVI" ]);

  (* abstract *)
  if !print_abstract then begin
    try
      let a = Bibtex.get_field e "abstract" in
	if is_url a then begin
	  output_string ch ", ";
	  Html.open_href ch (get_url a);
	  output_string ch "Abstract";
	  Html.close_href ch;
	end else begin
	  Html.paragraph ch; output_string ch "\n";
	  Html.open_balise ch "font size=-1"; Html.open_balise ch "blockquote";
	  output_string ch "\n";
	  latex2html ch a;
	  Html.close_balise ch "blockquote"; Html.close_balise ch "font";
	  output_string ch "\n";
	  Html.paragraph ch; output_string ch "\n"
	end
    with Not_found -> ()
  end
  

(* summary file f.html *)

let one_entry_summary basen ch (_,b,((_,k,f) as e)) =
  if !debug then begin
    Printf.printf "[%s]" k; flush stdout
  end;
  output_string ch "\n\n";
  Html.open_balise ch "tr valign=top";

  output_string ch "\n";
  Html.open_balise ch "td";
  Html.anchor ch k;
  if not !nokeys then
    latex2html ch ("[" ^ (Hashtbl.find cite_tab k) ^ "]");

  output_string ch "\n";
  Html.open_balise ch "td";
  latex2html ch b;
  Html.open_balise ch "BR";
  output_string ch "\n";

  Html.open_href ch (Printf.sprintf "%s-bib.html#%s" !directory k);
  output_string ch "BibTeX entry";
  Html.close_href ch;
  make_links ch e;

  Html.paragraph ch;
  output_string ch "\n"

let summary basen bl =
  let filename = basen ^ !suffix in
  Printf.printf "Making HTML document (%s)..." filename; flush stdout;
  let ch = open_out filename in
    if not !nodoc then
      Html.open_document ch (fun () -> output_string ch !title);
    header ch;
    if !title_spec then Html.h1_title ch !title;
    output_string ch "\n";

    in_summary := true;
    List.iter
      (fun (name,el) ->
	 begin match name with
	     None -> ()
	   | Some s ->
	       Html.open_balise ch "H2";
	       latex2html ch s;
	       Html.close_balise ch "H2";
	       output_string ch "\n"
	 end;
	 Html.open_balise ch "table";
	 List.iter (one_entry_summary basen ch) el;
	 Html.close_balise ch "table")
      bl;
    in_summary := false;
    if not !nodoc then begin
      if !print_footer then footer ch;
      Html.close_document ch
    end;
    close_out ch;
    Printf.printf "ok\n"; flush stdout


(* HTML file with BibTeX entries f-bib.html *)

let bib_file f bl =
  let fn = f ^ "-bib.html" in
  Printf.printf "Making HTML list of BibTeX entries (%s)..." fn;
  flush stdout;
  let ch = open_out fn in

  if not !nodoc then
    Html.open_document ch (fun _ -> output_string ch (f ^ ".bib"));

  Html.open_balise ch "H1";
  output_string ch (f ^ ".bib");
  Html.close_balise ch "H1";

  Html.open_balise ch "PRE";

  List.iter
    (fun (_,l) ->
       List.iter (fun (_,_,(t,k,fs)) ->
		    Html.anchor ch k;
		    output_string ch ("@" ^ t ^ "{" ^ k ^ ",\n");
		    List.iter
		      (fun (a,v) ->
			 output_string ch "  ";
			 output_string ch (String.lowercase a);
			 output_string ch " = ";
			 if a = "CROSSREF" then begin
			   output_string ch "{";
			   Html.open_href ch ("#" ^ v);
			   output_string ch v;
			   Html.close_href ch;
			   output_string ch "},\n"
			 end else
			   output_string ch ("{" ^ v ^ "},\n")
		      ) fs;
		    output_string ch "}\n") l)
    bl;

  Html.close_balise ch "PRE";
  
  footer ch;
  if not !nodoc then Html.close_document ch;
  flush ch;
  close_out ch;
  Printf.printf "ok\n"; flush stdout


(* main function *)

let format_list f bl =
  first_pass bl;
  directory := f;
  summary f bl;
  bib_file f bl

