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
				     
let main args =
  let (expfname,outbasefname) =
    try
      (args.(1),(try Some args.(2) with _ -> None)) 
    with      
      Invalid_argument s ->
      Util.fail (Printf.sprintf "Usage: %s FILENAME OUTPUT_PREFIX\n" Sys.argv.(0))
  in
  Util.debug "Step 1/3: Loading experiment...";
  let (model,commands) = ModelLoader.load_experiment expfname in
  Util.debug "Step 2/3: Precomputing model checking table...";
  let checker = Checker.precompute model in
  let products =
    List.fold_left
      (fun accum command ->
       match command with
	 ModelLoader.Check (color,formula) ->
	 (match accum with
	    [] ->
	    (match outbasefname with
	       None -> Util.fail "no filename specified either on command line or in experiment file"
	     | Some fname -> [(fname,[(color,(checker formula))])])
	  | (fname,fmlas)::rem -> (fname,(color,(checker formula))::fmlas)::rem)
       | ModelLoader.Output fname ->
	  (fname,[])::accum)
      [] commands 
  in		   
  Util.debug "Step 3/3: Writing output files...";
  List.iter
    (fun (fname,colored_truth_vals) ->
     match colored_truth_vals with
       [] -> ()
     | _ ->
	for state = 0 to Model.Graph.nb_vertex model.Model.kripke - 1 do
	  let out_name =  (Printf.sprintf "%s-%s.dot" fname (model.Model.kripkeid state)) in
	  let output = open_out out_name in
	  PrinterGraph.vertex_attributes_fn := (fun point ->
						let col =
						  List.fold_left
						    (fun accum (color,truth_val) -> 
						  if truth_val state point
						  then color (* accum + color *) 
						  else accum)
						    0x000000 colored_truth_vals
					     in
					     if col == 0 then []
					     else [`Color col; `Style `Filled]);
	  PrinterGraph.vertex_name_fn := model.Model.spaceid;
	  Printer.output_graph output model.Model.space;
	  close_out output
	done)
    products;
  Util.debug "All done."

let _ = main Sys.argv
