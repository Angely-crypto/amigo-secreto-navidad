import { describe, expect, it } from 'vitest';
import { drawSecretSanta, randomIndex } from '../src/lib/draw';
const people=[{id:'a',name:'Ana'},{id:'b',name:'Beto'},{id:'c',name:'Cami'},{id:'d',name:'Diego'}];
describe('sorteo',()=>{
 it('asigna una vez, sin autoasignación ni destinatarios repetidos',()=>{
  const result=drawSecretSanta(people);
  expect(result).toHaveLength(people.length);
  expect(result.every(x=>x.giverId!==x.receiverId)).toBe(true);
  expect(new Set(result.map(x=>x.receiverId)).size).toBe(people.length);
 });
 it('respeta exclusiones dirigidas',()=>{
  const result=drawSecretSanta(people,[['a','b'],['c','d']]);
  expect(result).not.toContainEqual({giverId:'a',receiverId:'b'});
  expect(result).not.toContainEqual({giverId:'c',receiverId:'d'});
 });
 it('detecta cuando no existe solución',()=>{
  expect(()=>drawSecretSanta(people,[['a','b'],['a','c'],['a','d']],100)).toThrow('No se encontró');
 });
 it('rechaza escenarios menores de dos personas',()=>expect(()=>drawSecretSanta([people[0]])).toThrow('al menos dos'));
 it('usa rechazo para mantener rango uniforme y se mantiene dentro del rango',()=>{
  let calls=0;const sequence=[new Uint8Array([255,255,255,255]),new Uint8Array([0,0,0,5])];
  const result=randomIndex(10,()=>sequence[calls++]);expect(result).toBe(5);expect(calls).toBe(2);
 });
});
