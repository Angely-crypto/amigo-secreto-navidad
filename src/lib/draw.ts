export type DrawPerson = { id: string; name: string };
export function randomIndex(max: number, randomBytes: (n: number) => Uint8Array = n => crypto.getRandomValues(new Uint8Array(n))): number {
  if (!Number.isSafeInteger(max) || max < 1 || max > 0xffffffff) throw new RangeError('max debe estar entre 1 y 2^32-1');
  const limit = 0x100000000 - (0x100000000 % max);
  for (;;) {
    const b = randomBytes(4);
    const value = (b[0] * 0x1000000 + b[1] * 0x10000 + b[2] * 0x100 + b[3]) >>> 0;
    if (value < limit) return value % max;
  }
}
/** Rejection sampling gives a uniform choice among valid assignments when the CSPRNG is uniform. */
export function drawSecretSanta(people: DrawPerson[], exclusions: Array<[string, string]> = [], maxAttempts = 10000,
  index: (max: number) => number = max => randomIndex(max)) {
  if (people.length < 2) throw new Error('Se necesitan al menos dos participantes.');
  if (new Set(people.map(p => p.id)).size !== people.length) throw new Error('Los participantes deben ser únicos.');
  const forbidden = new Set(exclusions.map(([a,b]) => `${a}\0${b}`));
  for (let attempt=0; attempt<maxAttempts; attempt++) {
    const recipients = [...people];
    for (let i=recipients.length-1;i>0;i--) { const j=index(i+1); [recipients[i],recipients[j]]=[recipients[j],recipients[i]]; }
    if (people.every((giver,i)=>giver.id!==recipients[i].id&&!forbidden.has(`${giver.id}\0${recipients[i].id}`)))
      return people.map((giver,i)=>({giverId:giver.id,receiverId:recipients[i].id}));
  }
  throw new Error('No se encontró una asignación válida. Revisa las exclusiones.');
}
