# Examples

    evaluate('age >= 18 and country in ["FI", "SE"]', {"age": 20, "country": "FI"})  -> True
    evaluate('coalesce(nick, name.first, "anon")', {"name": {"first": "Ada"}})       -> 'Ada'
    evaluate('len(tags) > 2 or "vip" in tags', {"tags": ["vip"]})                     -> True
    evaluate('price * qty', {"price": 2.5, "qty": 4})                                  -> 10.0
    evaluate('a ==', {})   raises FilterSyntaxError('unexpected end of input at column 5')
