module PrinterGraph =
  struct
    include Model.Graph

    let vertex_attributes_fn = ref (fun v -> Util.fail "Printer not initialized")
    let vertex_name_fn = ref (fun v -> Util.fail "Printer not initialized")

    let edge_attributes e = []
    let default_edge_attributes g = [`Dir `Forward]
    let get_subgraph g = None
    let vertex_attributes v = !vertex_attributes_fn v
    let graph_attributes g = []
    let vertex_name v = !vertex_name_fn v
    let default_vertex_attributes g = []			      
  end

module Printer = Graph.Graphviz.Neato(PrinterGraph)

let vertex_color colored_truth_vals state point =
    List.fold_left
      (fun accum (color,truth_val) -> 
       if truth_val state point
       then color (* accum + color *) 
       else accum)
      0x000000 colored_truth_vals
      
let write_state model state colored_truth_vals (output : out_channel) =
    PrinterGraph.vertex_attributes_fn :=
      (fun point ->
       let col = vertex_color colored_truth_vals state point in
       if col == 0 then []
       else [`Color col; `Style `Filled]);
    PrinterGraph.vertex_name_fn := model.Model.spaceid;
    Printer.output_graph output model.Model.space

let alternate_write_state model state colored_truth_vals (output : out_channel) space_fname =
  (* TODO this is a quick hack for quick saving... *)
  let input = open_in space_fname in
  let l1 = input_line input in
  if not (Str.string_match (Str.regexp_case_fold "[' ' '\t']*digraph[^{]*") l1 0)
  then (close_in input; write_state model state colored_truth_vals output)
  else
    begin
      Printf.fprintf output "%s\n" l1;
      for point = 0 to Model.Graph.nb_vertex model.Model.space - 1 do
	let col = vertex_color colored_truth_vals state point in
	Printf.fprintf output "%d [fillcolor=\"#%06X\",style=\"filled\"];\n" point (if col == 0 then 0xFFFFFF else col)
      done;
      try
	while true do
	  Printf.fprintf output "%s\n" (input_line input)
	done
      with End_of_file -> close_in input
    end
      
let run_interactive model env checker =
  try
    while true do
      let line = read_line () in
      let (ide,points,qformula) = ModelLoader.load_ask_query env line in
      let res =  (Checker.qchecker (List.map model.Model.idspace points)
		    (Model.Graph.nb_vertex model.Model.space) checker qformula)
      in
      Printf.printf "%s: %f\n%!" ide res
    done
  with End_of_file -> ()
      
let main args =
  let (expfname,outbasefname) =
    try
      (args.(1),(try Some args.(2) with _ -> None)) 
    with      
      Invalid_argument s ->
      Util.fail (Printf.sprintf "Usage: %s FILENAME OUTPUT_PREFIX\n" Sys.argv.(0))
  in
  Util.debug "Step 1/3: Loading experiment...";
  let (model,env,commands) = ModelLoader.load_experiment expfname in
  (* TODO: check for output commands here! *)
  Util.debug "Step 2/3: Precomputing model checking table...";
  let t = Sys.time () in
  let checker = Checker.precompute model in
  let products =
    List.fold_left
      (fun accum command ->
	match command with
	  ModelLoader.Ask (ide,ids,qformula) ->
	    Util.debug "Ask queries are supported only in server mode (see readme)"; []
	| ModelLoader.Check (color,formula) ->
	   (match accum with
	     [] ->
	       (match outbasefname with
		 None -> Util.fail "no filename specified either on command line or in experiment file"
	       | Some fname -> [((fname,None),[(color,(checker formula))])])
	   | (fname,fmlas)::rem -> (fname,(color,(checker formula))::fmlas)::rem)
	| ModelLoader.Output (fname,states) ->
	   ((fname,states),[])::accum)
      [] commands 
  in
  match products with
    [] ->
      Util.debug "Step 3/3: Interactive evaluation of Ask queries";
      run_interactive model env checker
  | _ ->
     begin
       let t' = (Sys.time ()) -. t in
       Util.debug (Printf.sprintf "Computation time (in seconds): %f" t');
       Util.debug "Step 3/3: Writing output files...";
       List.iter
	 (fun ((fname,states),colored_truth_vals) ->
	   match colored_truth_vals with
	     [] -> ()
	   | _ ->
	      let aux fn =
		match states with
		  None ->
		    for state = 0
		      to Model.Graph.nb_vertex model.Model.kripke - 1
		    do
		      fn state;
		    done;
		| Some lst -> List.iter fn lst
	      in
	      let fn state =
		let out_name =  (Printf.sprintf "%s-%s.dot" fname (model.Model.kripkeid state)) in
		let output = open_out out_name in
		alternate_write_state model state (List.rev colored_truth_vals) output model.Model.local_state.DotParser.spacefname;
		close_out output
	      in
	      aux fn)
	 products;
       Util.debug "All done."
     end
       
let _ = main Sys.argv
