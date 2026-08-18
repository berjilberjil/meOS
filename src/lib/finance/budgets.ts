import { budgetRollup, type BudgetLine } from './calc';

export { budgetRollup, type BudgetLine };

export function budgetTotals(lines: BudgetLine[]): { spent_paise: number; budget_paise: number } {
	return lines.reduce(
		(acc, l) => ({ spent_paise: acc.spent_paise + l.spent_paise, budget_paise: acc.budget_paise + l.budget_paise }),
		{ spent_paise: 0, budget_paise: 0 }
	);
}
