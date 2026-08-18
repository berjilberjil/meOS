import { SupabaseRepository } from '$lib/data/repository';
import type { Investment } from './types';

export const investmentsRepo = new SupabaseRepository<Investment>('investments');

export async function setCurrentValue(id: string, valuePaise: number): Promise<Investment> {
	return investmentsRepo.update(id, { current_value_paise: valuePaise } as Partial<Investment>);
}
