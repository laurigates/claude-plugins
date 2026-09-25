// a pattern the text does not state as a literal matches at most once per position
'aaaaaaaaaaaaaaaaaaaa'.replace(new RegExp('a', 'g'), () => agent('x'));
