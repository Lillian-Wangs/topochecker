type formula =
    T
  | Prop of string
  | QProp of (string * string * float)
  | Not of formula
  | And of formula * formula
  | Near of formula
  | Surrounded of formula * formula 
  | Ex of formula
  | Af of formula
  | Eu of formula * formula     
