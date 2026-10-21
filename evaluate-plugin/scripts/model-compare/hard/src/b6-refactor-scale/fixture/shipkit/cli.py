import argparse

from .pricing import calc_shipping


def main(argv=None):
    parser = argparse.ArgumentParser(prog="shipkit")
    parser.add_argument("--zone", required=True)
    parser.add_argument("--weight", type=float, required=True)
    parser.add_argument("--express", action="store_true")
    args = parser.parse_args(argv)
    price = calc_shipping(args.weight, args.zone, args.express)
    line = f"{args.zone} {args.weight:g} kg {'express' if args.express else 'standard'}: {price:.2f} EUR"
    print(line)
    return line


if __name__ == "__main__":
    main()
