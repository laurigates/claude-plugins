// TEST FILE: Contains explicit any type usage
// Should trigger TypeScript strictness detection

// Explicit any types
const userData: any = { name: "John", age: 30 };
const config: any = loadConfig();

// Function with any parameters and return
function processData(input: any): any {
  return input.map((item: any) => item.value);
}

// any in generics
const items: Array<any> = [1, "two", { three: 3 }];
const map: Map<string, any> = new Map();

// Type assertion to any
function unsafeConvert(value: unknown) {
  return (value as any).someProperty;
}

// any[] array type
function mergeArrays(a: any[], b: any[]): any[] {
  return [...a, ...b];
}

// Object with any values
interface LooseConfig {
  settings: any;
  options: { [key: string]: any };
}

// @ts-ignore without explanation
// @ts-ignore
const badValue = undefined.property;

// @ts-expect-error without explanation
// @ts-expect-error
const anotherBad: number = "string";

function loadConfig() {
  return {};
}

export { userData, config, processData, items, map, unsafeConvert, mergeArrays };
