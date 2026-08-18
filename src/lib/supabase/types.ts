export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      accounts: {
        Row: {
          archived: boolean
          balance_paise: number
          created_at: string
          currency: string
          id: string
          name: string
          opening_balance_paise: number
          type: string
          updated_at: string
          user_id: string
        }
        Insert: {
          archived?: boolean
          balance_paise?: number
          created_at?: string
          currency?: string
          id?: string
          name: string
          opening_balance_paise?: number
          type: string
          updated_at?: string
          user_id?: string
        }
        Update: {
          archived?: boolean
          balance_paise?: number
          created_at?: string
          currency?: string
          id?: string
          name?: string
          opening_balance_paise?: number
          type?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      belongings: {
        Row: {
          acquired_on: string | null
          category: string
          cost_paise: number | null
          created_at: string
          id: string
          image_path: string | null
          kind: string
          name: string
          notes: string | null
          qty: number
          user_id: string
        }
        Insert: {
          acquired_on?: string | null
          category: string
          cost_paise?: number | null
          created_at?: string
          id?: string
          image_path?: string | null
          kind: string
          name?: string
          notes?: string | null
          qty?: number
          user_id?: string
        }
        Update: {
          acquired_on?: string | null
          category?: string
          cost_paise?: number | null
          created_at?: string
          id?: string
          image_path?: string | null
          kind?: string
          name?: string
          notes?: string | null
          qty?: number
          user_id?: string
        }
        Relationships: []
      }
      categories: {
        Row: {
          color: string | null
          created_at: string
          icon: string | null
          id: string
          kind: string
          monthly_budget_paise: number
          name: string
          updated_at: string
          user_id: string
        }
        Insert: {
          color?: string | null
          created_at?: string
          icon?: string | null
          id?: string
          kind: string
          monthly_budget_paise?: number
          name: string
          updated_at?: string
          user_id?: string
        }
        Update: {
          color?: string | null
          created_at?: string
          icon?: string | null
          id?: string
          kind?: string
          monthly_budget_paise?: number
          name?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      fitness_logs: {
        Row: {
          activity: string
          calories: number | null
          created_at: string
          distance_m: number | null
          duration_min: number
          id: string
          logged_on: string
          notes: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          activity: string
          calories?: number | null
          created_at?: string
          distance_m?: number | null
          duration_min?: number
          id?: string
          logged_on: string
          notes?: string | null
          updated_at?: string
          user_id?: string
        }
        Update: {
          activity?: string
          calories?: number | null
          created_at?: string
          distance_m?: number | null
          duration_min?: number
          id?: string
          logged_on?: string
          notes?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      goals: {
        Row: {
          created_at: string
          description: string | null
          id: string
          status: string
          target_date: string | null
          title: string
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          description?: string | null
          id?: string
          status?: string
          target_date?: string | null
          title: string
          updated_at?: string
          user_id?: string
        }
        Update: {
          created_at?: string
          description?: string | null
          id?: string
          status?: string
          target_date?: string | null
          title?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      health_logs: {
        Row: {
          created_at: string
          id: string
          logged_on: string
          mood: string | null
          notes: string | null
          sleep_min: number | null
          updated_at: string
          user_id: string
          water_ml: number | null
          weight_g: number | null
        }
        Insert: {
          created_at?: string
          id?: string
          logged_on: string
          mood?: string | null
          notes?: string | null
          sleep_min?: number | null
          updated_at?: string
          user_id?: string
          water_ml?: number | null
          weight_g?: number | null
        }
        Update: {
          created_at?: string
          id?: string
          logged_on?: string
          mood?: string | null
          notes?: string | null
          sleep_min?: number | null
          updated_at?: string
          user_id?: string
          water_ml?: number | null
          weight_g?: number | null
        }
        Relationships: []
      }
      investments: {
        Row: {
          created_at: string
          current_value_paise: number
          id: string
          invested_paise: number
          name: string
          sip_amount_paise: number | null
          sip_day: number | null
          type: string
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          current_value_paise?: number
          id?: string
          invested_paise?: number
          name: string
          sip_amount_paise?: number | null
          sip_day?: number | null
          type: string
          updated_at?: string
          user_id?: string
        }
        Update: {
          created_at?: string
          current_value_paise?: number
          id?: string
          invested_paise?: number
          name?: string
          sip_amount_paise?: number | null
          sip_day?: number | null
          type?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      journal_entries: {
        Row: {
          body_json: Json
          body_text: string
          created_at: string
          id: string
          mood: string | null
          occurred_on: string
          title: string
          updated_at: string
          user_id: string
        }
        Insert: {
          body_json?: Json
          body_text?: string
          created_at?: string
          id?: string
          mood?: string | null
          occurred_on: string
          title?: string
          updated_at?: string
          user_id?: string
        }
        Update: {
          body_json?: Json
          body_text?: string
          created_at?: string
          id?: string
          mood?: string | null
          occurred_on?: string
          title?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      links: {
        Row: {
          created_at: string
          id: string
          relation: string
          source_id: string
          source_type: string
          target_id: string
          target_type: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          relation: string
          source_id: string
          source_type: string
          target_id: string
          target_type: string
          user_id?: string
        }
        Update: {
          created_at?: string
          id?: string
          relation?: string
          source_id?: string
          source_type?: string
          target_id?: string
          target_type?: string
          user_id?: string
        }
        Relationships: []
      }
      media_assets: {
        Row: {
          created_at: string
          duration_ms: number | null
          height: number | null
          id: string
          mime: string
          owner_id: string | null
          owner_type: string
          size_bytes: number
          storage_path: string
          thumbnail_path: string | null
          user_id: string
          width: number | null
        }
        Insert: {
          created_at?: string
          duration_ms?: number | null
          height?: number | null
          id?: string
          mime: string
          owner_id?: string | null
          owner_type: string
          size_bytes?: number
          storage_path: string
          thumbnail_path?: string | null
          user_id?: string
          width?: number | null
        }
        Update: {
          created_at?: string
          duration_ms?: number | null
          height?: number | null
          id?: string
          mime?: string
          owner_id?: string | null
          owner_type?: string
          size_bytes?: number
          storage_path?: string
          thumbnail_path?: string | null
          user_id?: string
          width?: number | null
        }
        Relationships: []
      }
      notes: {
        Row: {
          body_json: Json
          body_text: string
          created_at: string
          id: string
          pinned: boolean
          title: string
          updated_at: string
          user_id: string
        }
        Insert: {
          body_json?: Json
          body_text?: string
          created_at?: string
          id?: string
          pinned?: boolean
          title?: string
          updated_at?: string
          user_id?: string
        }
        Update: {
          body_json?: Json
          body_text?: string
          created_at?: string
          id?: string
          pinned?: boolean
          title?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      profile: {
        Row: {
          created_at: string
          display_name: string | null
          preferences: Json
          user_id: string
        }
        Insert: {
          created_at?: string
          display_name?: string | null
          preferences?: Json
          user_id: string
        }
        Update: {
          created_at?: string
          display_name?: string | null
          preferences?: Json
          user_id?: string
        }
        Relationships: []
      }
      recurring: {
        Row: {
          account_id: string
          active: boolean
          amount_paise: number
          cadence: string
          category_id: string | null
          created_at: string
          id: string
          interval_days: number | null
          investment_id: string | null
          kind: string
          name: string
          next_run_on: string
          plan: string | null
          renews_on: string | null
          updated_at: string
          user_id: string
          vendor: string | null
        }
        Insert: {
          account_id: string
          active?: boolean
          amount_paise: number
          cadence: string
          category_id?: string | null
          created_at?: string
          id?: string
          interval_days?: number | null
          investment_id?: string | null
          kind: string
          name: string
          next_run_on: string
          plan?: string | null
          renews_on?: string | null
          updated_at?: string
          user_id?: string
          vendor?: string | null
        }
        Update: {
          account_id?: string
          active?: boolean
          amount_paise?: number
          cadence?: string
          category_id?: string | null
          created_at?: string
          id?: string
          interval_days?: number | null
          investment_id?: string | null
          kind?: string
          name?: string
          next_run_on?: string
          plan?: string | null
          renews_on?: string | null
          updated_at?: string
          user_id?: string
          vendor?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "recurring_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: false
            referencedRelation: "accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recurring_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recurring_investment_id_fkey"
            columns: ["investment_id"]
            isOneToOne: false
            referencedRelation: "investments"
            referencedColumns: ["id"]
          },
        ]
      }
      savings_goals: {
        Row: {
          account_id: string | null
          created_at: string
          deadline: string | null
          id: string
          name: string
          saved_paise: number
          target_paise: number
          updated_at: string
          user_id: string
        }
        Insert: {
          account_id?: string | null
          created_at?: string
          deadline?: string | null
          id?: string
          name: string
          saved_paise?: number
          target_paise: number
          updated_at?: string
          user_id?: string
        }
        Update: {
          account_id?: string | null
          created_at?: string
          deadline?: string | null
          id?: string
          name?: string
          saved_paise?: number
          target_paise?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "savings_goals_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: false
            referencedRelation: "accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      streak_settings: {
        Row: {
          created_at: string
          freezes_total: number
          streak_goal: number
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          freezes_total?: number
          streak_goal?: number
          updated_at?: string
          user_id?: string
        }
        Update: {
          created_at?: string
          freezes_total?: number
          streak_goal?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      todos: {
        Row: {
          created_at: string
          done: boolean
          due_on: string | null
          id: string
          notes: string | null
          priority: number
          title: string
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          done?: boolean
          due_on?: string | null
          id?: string
          notes?: string | null
          priority?: number
          title: string
          updated_at?: string
          user_id?: string
        }
        Update: {
          created_at?: string
          done?: boolean
          due_on?: string | null
          id?: string
          notes?: string | null
          priority?: number
          title?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      transactions: {
        Row: {
          account_id: string
          amount_paise: number
          category_id: string | null
          created_at: string
          id: string
          note: string | null
          occurred_on: string
          recurring_id: string | null
          transfer_account_id: string | null
          type: string
          updated_at: string
          user_id: string
        }
        Insert: {
          account_id: string
          amount_paise: number
          category_id?: string | null
          created_at?: string
          id?: string
          note?: string | null
          occurred_on: string
          recurring_id?: string | null
          transfer_account_id?: string | null
          type: string
          updated_at?: string
          user_id?: string
        }
        Update: {
          account_id?: string
          amount_paise?: number
          category_id?: string | null
          created_at?: string
          id?: string
          note?: string | null
          occurred_on?: string
          recurring_id?: string | null
          transfer_account_id?: string | null
          type?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "transactions_account_id_fkey"
            columns: ["account_id"]
            isOneToOne: false
            referencedRelation: "accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "transactions_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "transactions_recurring_id_fkey"
            columns: ["recurring_id"]
            isOneToOne: false
            referencedRelation: "recurring"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "transactions_transfer_account_id_fkey"
            columns: ["transfer_account_id"]
            isOneToOne: false
            referencedRelation: "accounts"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      [_ in never]: never
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {},
  },
} as const

